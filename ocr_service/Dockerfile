FROM python:3.12-slim AS llama-cpp-builder

ARG LLAMA_CPP_REF=b9360

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential ca-certificates cmake git && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN git clone --depth 1 --branch "${LLAMA_CPP_REF}" https://github.com/ggml-org/llama.cpp.git /tmp/llama.cpp && \
    cmake -S /tmp/llama.cpp -B /tmp/llama.cpp/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DGGML_NATIVE=OFF && \
    cmake --build /tmp/llama.cpp/build --target llama-server --parallel && \
    cmake --install /tmp/llama.cpp/build --prefix /opt/llama.cpp

FROM python:3.12-slim

ENV LLAMA_CPP_BINARY=/opt/llama.cpp/bin/llama-server \
    LLAMA_CPP_NGL=0 \
    PATH="/opt/llama.cpp/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    SURYA_INFERENCE_BACKEND=llamacpp \
    SURYA_INFERENCE_KEEP_ALIVE=1 \
    SURYA_INFERENCE_PARALLEL=1

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates libgomp1 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY --from=llama-cpp-builder /opt/llama.cpp /opt/llama.cpp

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
