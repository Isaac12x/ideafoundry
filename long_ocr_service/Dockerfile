FROM python:3.12-slim

ARG LLAMA_CPP_REF=b9360
ARG TARGETARCH

# Reuse the ocr_service approach: download official llama.cpp release binaries
# (which include llama-server with multimodal / mtmd support) rather than
# compiling in-container. curl is kept for runtime GGUF downloads.
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
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV LD_LIBRARY_PATH=/opt/llama.cpp \
    PATH="/opt/llama.cpp:${PATH}" \
    LLAMA_NGL=0 \
    LLAMA_CTX_SIZE=8192 \
    MODEL_DIR=/models

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
