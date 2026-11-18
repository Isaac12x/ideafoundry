FROM python:3.12-slim

ARG LLAMA_CPP_REF=b9360
ARG TARGETARCH

COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /uvx /bin/

# Download official llama.cpp release binaries instead of compiling in-container.
# Building llama.cpp needs several GB of RAM per compiler process and routinely
# OOM-kills cc1plus inside Docker (especially on Docker Desktop defaults).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl libgomp1 && \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    case "${ARCH}" in \
      arm64|aarch64) LLAMA_ARCH=ubuntu-arm64 ;; \
      amd64|x86_64) LLAMA_ARCH=ubuntu-x64 ;; \
      *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL \
      "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_CPP_REF}/llama-${LLAMA_CPP_REF}-bin-${LLAMA_ARCH}.tar.gz" \
      | tar -xzf - -C /opt && \
    mv "/opt/llama-${LLAMA_CPP_REF}" /opt/llama.cpp && \
    test -x /opt/llama.cpp/llama-server && \
    apt-get purge -y curl && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV LLAMA_CPP_BINARY=/opt/llama.cpp/llama-server \
    LLAMA_CPP_NGL=0 \
    LD_LIBRARY_PATH=/opt/llama.cpp \
    PATH="/opt/llama.cpp:${PATH}" \
    PYTHONUNBUFFERED=1 \
    SURYA_INFERENCE_BACKEND=llamacpp \
    SURYA_INFERENCE_KEEP_ALIVE=1 \
    SURYA_INFERENCE_PARALLEL=1

WORKDIR /app
COPY requirements.txt overrides.txt ./
RUN uv pip install \
      --system \
      --no-cache \
      --requirement requirements.txt \
      --override overrides.txt && \
    python -c "import PIL; from surya.inference import SuryaInferenceManager; from surya.recognition import RecognitionPredictor; assert PIL.__version__ == '12.3.0'"
COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
