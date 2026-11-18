import io
import os
import re
import threading
from functools import lru_cache
from typing import Any

import fitz
from bs4 import BeautifulSoup
from fastapi import FastAPI, Header, HTTPException, Query, Request, Response
from PIL import Image

app = FastAPI(title="Idea Foundry Local OCR")


def int_env(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


PDF_DPI = max(72, int_env("OCR_PDF_DPI", 192))
PAGE_BATCH_SIZE = max(1, int_env("OCR_PAGE_BATCH_SIZE", 4))
SURYA_MODEL = os.environ.get("SURYA_MODEL_CHECKPOINT", "datalab-to/surya-ocr-2")
# Documents with more pages than this are routed to the heavy on-demand
# Unlimited-OCR pipeline instead of the synchronous Surya path.
LONG_DOC_PAGE_THRESHOLD = max(1, int_env("OCR_LONG_DOC_PAGE_THRESHOLD", 10))
# Rasterization DPI for the heavy pipeline (kept moderate to bound VLM image size).
LONG_RENDER_DPI = max(72, int_env("OCR_LONG_RENDER_DPI", 144))
surya_lock = threading.Lock()

PDF_FILENAMES = (".pdf",)
IMAGE_FILENAMES = (".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff")


def is_pdf(kind: str, filename: str) -> bool:
    return kind == "application/pdf" or filename.lower().endswith(PDF_FILENAMES)


def is_image(kind: str, filename: str) -> bool:
    return kind.startswith("image/") or filename.lower().endswith(IMAGE_FILENAMES)


def page_count_for(data: bytes, kind: str, filename: str) -> int:
    if is_pdf(kind, filename):
        doc = fitz.open(stream=data, filetype="pdf")
        try:
            return doc.page_count
        finally:
            doc.close()
    if is_image(kind, filename):
        return 1
    return 0


def render_single_page(data: bytes, kind: str, filename: str, page: int, dpi: int) -> bytes:
    if is_pdf(kind, filename):
        doc = fitz.open(stream=data, filetype="pdf")
        try:
            if page < 1 or page > doc.page_count:
                raise HTTPException(status_code=404, detail="page out of range")
            pix = doc.load_page(page - 1).get_pixmap(dpi=dpi, alpha=False)
            return pix.tobytes("png")
        finally:
            doc.close()
    if is_image(kind, filename):
        if page != 1:
            raise HTTPException(status_code=404, detail="page out of range")
        buffer = io.BytesIO()
        load_image(data).save(buffer, format="PNG")
        return buffer.getvalue()
    raise HTTPException(status_code=415, detail="unsupported document type")


def split_parts(text: str) -> list[str]:
    lines = [
        re.sub(r"\s+", " ", line).strip(" -\u2022\t")
        for line in text.splitlines()
    ]
    parts = [line for line in lines if len(line) >= 2]
    return parts[:100]


def normalize_text(text: str) -> str:
    lines = [
        re.sub(r"[ \t\r\f\v]+", " ", line).strip()
        for line in text.splitlines()
    ]
    return "\n".join(line for line in lines if line)


def html_to_text(fragment: str) -> str:
    if not fragment:
        return ""

    soup = BeautifulSoup(fragment, "html.parser")

    for br in soup.find_all("br"):
        br.replace_with("\n")

    for table in soup.find_all("table"):
        rows: list[str] = []
        for row in table.find_all("tr"):
            cells = [
                cell.get_text(" ", strip=True)
                for cell in row.find_all(["th", "td"])
            ]
            if cells:
                rows.append(" | ".join(cells))
        table.replace_with("\n".join(rows))

    return normalize_text(soup.get_text("\n", strip=True))


@lru_cache(maxsize=1)
def recognition_predictor() -> Any:
    from surya.inference import SuryaInferenceManager
    from surya.recognition import RecognitionPredictor

    manager = SuryaInferenceManager()
    return RecognitionPredictor(manager)


def load_image(data: bytes) -> Image.Image:
    with Image.open(io.BytesIO(data)) as image:
        return image.convert("RGB")


def render_pdf_pages(data: bytes) -> list[Image.Image]:
    doc = fitz.open(stream=data, filetype="pdf")
    try:
        images: list[Image.Image] = []
        for page in doc:
            pix = page.get_pixmap(dpi=PDF_DPI, alpha=False)
            with Image.open(io.BytesIO(pix.tobytes("png"))) as image:
                images.append(image.convert("RGB"))
        return images
    finally:
        doc.close()


def block_metadata(block: Any) -> dict[str, Any]:
    data = block.model_dump() if hasattr(block, "model_dump") else {}
    metadata: dict[str, Any] = {}

    for key in [
        "label",
        "raw_label",
        "reading_order",
        "html",
        "polygon",
        "bbox",
        "confidence",
        "skipped",
        "error",
    ]:
        value = data.get(key, getattr(block, key, None))
        if value is not None:
            metadata[key] = value

    return metadata


def page_text_and_metadata(
    page: Any,
    page_number: int,
) -> tuple[str, str, dict[str, Any]]:
    blocks = sorted(
        list(getattr(page, "blocks", [])),
        key=lambda block: getattr(block, "reading_order", 0),
    )
    block_html = [
        getattr(block, "html", "")
        for block in blocks
        if not getattr(block, "skipped", False) and not getattr(block, "error", False)
    ]
    block_text = [html_to_text(html) for html in block_html]
    html = "\n".join(fragment for fragment in block_html if fragment)
    text = "\n".join(part for part in block_text if part)
    metadata = {
        "page": page_number,
        "html": html,
        "text": text,
        "image_bbox": list(getattr(page, "image_bbox", [])),
        "blocks": [block_metadata(block) for block in blocks],
    }
    return text, html, metadata


def extract_images(images: list[Image.Image]) -> tuple[str, str, list[dict[str, Any]]]:
    page_text: list[str] = []
    page_html: list[str] = []
    pages: list[dict[str, Any]] = []

    for start in range(0, len(images), PAGE_BATCH_SIZE):
        batch = images[start : start + PAGE_BATCH_SIZE]
        with surya_lock:
            predictions = recognition_predictor()(batch, full_page=True)

        for offset, page in enumerate(predictions):
            text, html, metadata = page_text_and_metadata(page, start + offset + 1)
            page_text.append(text)
            page_html.append(html)
            pages.append(metadata)

    return (
        "\n\n".join(text for text in page_text if text),
        "\n\n".join(html for html in page_html if html),
        pages,
    )


def extract_pdf(data: bytes) -> tuple[str, str, list[dict[str, Any]]]:
    return extract_images(render_pdf_pages(data))


def extract_image(data: bytes) -> tuple[str, str, list[dict[str, Any]]]:
    return extract_images([load_image(data)])


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "engine": "surya"}


@app.post("/probe")
async def probe(
    request: Request,
    content_type: str | None = Header(default=None),
    x_filename: str | None = Header(default=None),
) -> dict[str, Any]:
    data = await request.body()
    filename = x_filename or "attachment"
    kind = (content_type or "").split(";")[0].lower()
    pages = page_count_for(data, kind, filename)
    return {
        "filename": filename,
        "content_type": kind,
        "page_count": pages,
        "threshold": LONG_DOC_PAGE_THRESHOLD,
        "needs_long": pages > LONG_DOC_PAGE_THRESHOLD,
    }


@app.post("/render")
async def render(
    request: Request,
    page: int = Query(1, ge=1),
    dpi: int | None = Query(default=None, ge=72, le=600),
    content_type: str | None = Header(default=None),
    x_filename: str | None = Header(default=None),
) -> Response:
    data = await request.body()
    filename = x_filename or "attachment"
    kind = (content_type or "").split(";")[0].lower()
    png = render_single_page(data, kind, filename, page, dpi or LONG_RENDER_DPI)
    return Response(content=png, media_type="image/png")


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
        text, html, pages = extract_pdf(data)
    elif kind.startswith("image/") or filename.lower().endswith(
        (".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff")
    ):
        text, html, pages = extract_image(data)
    elif kind.startswith("text/") or filename.lower().endswith(
        (".txt", ".md", ".csv")
    ):
        text = data.decode("utf-8", errors="replace")
        html = ""
        pages = []
    else:
        text = ""
        html = ""
        pages = []

    return {
        "filename": filename,
        "content_type": kind,
        "engine": "surya",
        "model": SURYA_MODEL,
        "html": html,
        "text": text,
        "parts": split_parts(text),
        "pages": pages,
    }
