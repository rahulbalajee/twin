from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from openai import AsyncOpenAI
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import asyncio
import json
import uuid
import logging
import boto3
from context import prompt
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)

load_dotenv(override=True)

app = FastAPI()

cors_origins = os.getenv("CORS_ORIGINS")
if not cors_origins:
    raise RuntimeError("CORS_ORIGINS is not set")

origins = [origin.strip() for origin in cors_origins.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    raise RuntimeError("OPENAI_API_KEY is not set")

client = AsyncOpenAI(api_key=api_key)

model = os.getenv("OPENAI_MODEL")
if not model:
    raise RuntimeError("OPENAI_MODEL is not set")

base_dir = Path(__file__).resolve().parent

use_s3 = os.getenv("USE_S3", "false").lower() == "true"

if use_s3:
    s3_bucket = os.getenv("S3_BUCKET")
    if not s3_bucket:
        raise RuntimeError("S3_BUCKET is not set when USE_S3=true")
    s3_client = boto3.client("s3")
else:
    memory_dir = Path(os.getenv("MEMORY_DIR") or base_dir.parent / "memory")
    memory_dir.mkdir(exist_ok=True)

def get_memory_key(session_id: str) -> str:
    return f"{session_id}.json"

def load_conversation(session_id: str) -> List[Dict]:
    if use_s3:
        try:
            response = s3_client.get_object(
                Bucket=s3_bucket,
                Key=get_memory_key(session_id),
                RequestPayer="requester",
            )
            return json.loads(response["Body"].read().decode("utf-8"))
        except s3_client.exceptions.NoSuchKey:
            return []
    file_path = memory_dir / get_memory_key(session_id)
    if file_path.exists():
        with open(file_path, "r", encoding="utf-8") as file:
            return json.load(file)
    return []

def save_conversation(session_id: str, messages: List[Dict]):
    if use_s3:
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=get_memory_key(session_id),
            Body=json.dumps(messages, indent=2, ensure_ascii=False),
            ContentType="application/json",
        )
        return
    file_path = memory_dir / get_memory_key(session_id)
    with open(file_path, "w", encoding="utf-8") as file:
        json.dump(messages, file, indent=2, ensure_ascii=False)

def list_session_ids() -> List[str]:
    if use_s3:
        response = s3_client.list_objects_v2(Bucket=s3_bucket)
        return [
            Path(obj["Key"]).stem
            for obj in response.get("Contents", [])
            if obj["Key"].endswith(".json")
        ]
    return [file_path.stem for file_path in memory_dir.glob("*.json")]

class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    session_id: Optional[str] = None

    @field_validator("session_id")
    @classmethod
    def validate_session_id(cls, value):
        if value is not None:
            return str(uuid.UUID(value))
        return value

class ChatResponse(BaseModel):
    response: str
    session_id: str
    is_new_session: bool

@app.get("/")
async def root():
    return {
        "message": "AI Digital Twin API",
        "memory_enabled": True,
        "memory_type": "s3" if use_s3 else "local",
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "use_s3": use_s3,
    }

@app.post("/chat")
async def chat(request: ChatRequest) -> ChatResponse:
    try:
        is_new_session = request.session_id is None
        session_id = request.session_id or str(uuid.uuid4())

        messages = [{"role": "system", "content": prompt()}]

        conversation = await asyncio.to_thread(load_conversation, session_id)
        for message in conversation:
            messages.append({"role": message["role"], "content": message["content"]})

        messages.append({"role": "user", "content": request.message})

        response = await client.chat.completions.create(
            model=model,
            messages=messages,
        )

        assistant_message = response.choices[0].message.content or ""

        conversation.append({"role": "user", "content": request.message, "timestamp": datetime.now(timezone.utc).isoformat()})
        conversation.append({"role": "assistant", "content": assistant_message, "timestamp": datetime.now(timezone.utc).isoformat()})
        
        await asyncio.to_thread(save_conversation, session_id, conversation)

        return ChatResponse(
            response=assistant_message,
            session_id=session_id,
            is_new_session=is_new_session,
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("chat request failed")
        raise HTTPException(status_code=500, detail="Something went wrong")

@app.get("/conversation/{session_id}")
async def get_conversation(session_id: str):
    try:
        session_id = str(uuid.UUID(session_id))
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid session ID")
    try:
        conversation = await asyncio.to_thread(load_conversation, session_id)
        return {"session_id": session_id, "messages": conversation}
    except Exception:
        logger.exception("get conversation failed")
        raise HTTPException(status_code=500, detail="Something went wrong")

@app.get("/sessions")
async def get_sessions():
    try:
        sessions = []
        for session_id in await asyncio.to_thread(list_session_ids):
            conversation = await asyncio.to_thread(load_conversation, session_id)
            if conversation:
                sessions.append({
                    "session_id": session_id,
                    "message_count": len(conversation),
                    "last_message": conversation[-1]["content"],
                })
        return {"sessions": sessions}
    except Exception:
        logger.exception("get sessions failed")
        raise HTTPException(status_code=500, detail="Something went wrong")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)