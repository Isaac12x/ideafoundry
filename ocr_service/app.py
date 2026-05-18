import io
import re
from typing import Any

import fitz
import pytesseract
from fastapi import FastAPI, Header, Request
from PIL import Image

app = FastAPI(title="Idea Foundry Local OCR")


def split_parts(text: str) -> list[str]:
    lines = [re.sub(r"\s+", " ", line).strip(" -•\t") for line in text.splitlines()]
    parts = [line for line in lines if len(line) >= 2]
    return parts[:100]


def ocr_image(data: bytes) -> str:
    image = Image.open(io.BytesIO(data))
    return pytesseract.image_to_string(image)


def extract_pdf(data: bytes) -> str:
    doc = fitz.open(stream=data, filetype="pdf")
    page_text: list[str] = []
    for page in doc:
        text = page.get_text().strip()
        if text:
            page_text.append(text)
            continue

        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        image = Image.open(io.BytesIO(pix.tobytes("png")))
        page_text.append(pytesseract.image_to_string(image))
    return "\n\n".join(page_text)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/extract")
async def extract(
    request: Request,
    content_type: str | None = Header(default=None),
    x_filename: str | None = Header(default=None),
) -> dict[str, Any]:
    data = await request.body()
    filename = x_filename or "attachment"
    kind = (content_type or "").split(";")[0].lower()

    if kind == "application/pdf" or filename.lower().endswith(".pdf"):
        text = extract_pdf(data)
    elif kind.startswith("image/"):
        text = ocr_image(data)
    elif kind.startswith("text/") or filename.lower().endswith((".txt", ".md", ".csv")):
        text = data.decode("utf-8", errors="replace")
    else:
        text = ""

    return {
        "filename": filename,
        "content_type": kind,
        "text": text,
        "parts": split_parts(text),
    }
