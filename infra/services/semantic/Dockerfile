FROM python:3.12-slim

ARG SEMANTIC_MODEL=BAAI/bge-small-en-v1.5
ENV SEMANTIC_MODEL=${SEMANTIC_MODEL} \
    SEMANTIC_DB=/data/semantic.sqlite3 \
    FASTEMBED_CACHE_PATH=/models \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Bake the model into the image so embedding works offline.
RUN python -c "import os; from fastembed import TextEmbedding; TextEmbedding(os.environ['SEMANTIC_MODEL'])"

COPY app.py .
RUN mkdir -p /data
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health').read()"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
