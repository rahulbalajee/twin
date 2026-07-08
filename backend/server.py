from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from openai import AsyncOpenAI
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import json
import uuid
from datetime import datetime
from pathlib import Path

load_dotenv(override=True)

app = FastAPI()

origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
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

BASE_DIR = Path(__file__).resolve().parent

memory_dir = BASE_DIR.parent / "memory"
memory_dir.mkdir(exist_ok=True)

def load_personality():
    with open(BASE_DIR / "me.txt", "r", encoding="utf-8") as file:
        return file.read().strip()

personality = load_personality()

def load_conversation(session_id: str) -> List[Dict]:
    file_path = memory_dir / f"{session_id}.json"
    if file_path.exists():
        with open(file_path, "r", encoding="utf-8") as file:
            return json.load(file)
    return []

def save_conversation(session_id: str, messages: List[Dict]):
    file_path = memory_dir / f"{session_id}.json"
    with open(file_path, "w", encoding="utf-8") as file:
        json.dump(messages, file, indent=2, ensure_ascii=False)

class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    session_id: str
    is_new_session: bool

@app.get("/")
async def root():
    return {"message": "AI Digital Twin API"}

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    try:
        is_new_session = request.session_id is None
        session_id = request.session_id or str(uuid.uuid4())

        conversation = load_conversation(session_id)

        messages = [{"role": "system", "content": personality}]

        for message in conversation:
            messages.append({"role": message["role"], "content": message["content"]})

        messages.append({"role": "user", "content": request.message})

        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
        )

        assistant_message = response.choices[0].message.content or ""
        conversation.append({"role": "user", "content": request.message, "timestamp": datetime.now().isoformat()})
        conversation.append({"role": "assistant", "content": assistant_message, "timestamp": datetime.now().isoformat()})
        save_conversation(session_id, conversation)

        return ChatResponse(
            response=assistant_message,
            session_id=session_id,
            is_new_session=is_new_session,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/sessions")
async def get_sessions():
    sessions = []
    for file_path in memory_dir.glob("*.json"):
        session_id = file_path.stem
        with open(file_path, "r", encoding="utf-8") as file:
            conversation = json.load(file)
        if conversation:
            sessions.append({
                "session_id": session_id,
                "message_count": len(conversation),
                "last_message": conversation[-1]["content"] if conversation else None,
            })
    return {"sessions": sessions}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)