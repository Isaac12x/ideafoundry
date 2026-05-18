FROM python:3.12-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y tesseract-ocr tesseract-ocr-eng poppler-utils && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
