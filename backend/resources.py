from pypdf import PdfReader
import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

base_dir = Path(__file__).resolve().parent
data_dir = base_dir / "data"

def load_linkedin() -> str:
    pdf_path = data_dir / "linkedin.pdf"
    if not pdf_path.exists():
        logger.warning("linkedin.pdf not found, skipping")
        return ""
    reader = PdfReader(pdf_path)
    return "\n".join(
        text for page in reader.pages if (text := page.extract_text())
    ).strip()

def load_text(filename: str) -> str:
    with open(data_dir / filename, "r", encoding="utf-8") as file:
        return file.read().strip()

def load_facts() -> dict:
    with open(data_dir / "facts.json", "r", encoding="utf-8") as file:
        return json.load(file)

linkedin = load_linkedin()
summary = load_text("summary.txt")
style = load_text("style.txt")
facts = load_facts()