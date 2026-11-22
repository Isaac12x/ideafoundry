FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1
ENV HERMES_HOME=/data
ENV LOCAL_INFERENCE_BASE_URL=http://host.docker.internal:8080/v1
ENV LOCAL_INFERENCE_MODEL=gpt-3.5-turbo
ENV LOCAL_INFERENCE_API_KEY=local

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ripgrep curl procps && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml README.md MANIFEST.in setup.py ./
COPY agent agent
COPY cron cron
COPY gateway gateway
COPY hermes_cli hermes_cli
COPY plugins plugins
COPY providers providers
COPY skills skills
COPY optional-skills optional-skills
COPY tools tools
COPY webapp_agent webapp_agent
COPY run_agent.py model_tools.py toolsets.py toolset_distributions.py ./
COPY hermes_bootstrap.py hermes_constants.py hermes_logging.py hermes_state.py hermes_time.py mcp_serve.py utils.py ./

RUN pip install --no-cache-dir ".[connectors]"

VOLUME ["/data"]
EXPOSE 8000

CMD ["uvicorn", "webapp_agent.api:app", "--host", "0.0.0.0", "--port", "8000"]
