from __future__ import annotations

from types import SimpleNamespace

from agent.agent_init import _requires_minimum_context
from agent.conversation_loop import _record_skill_review_iteration
from agent.context_compressor import ContextCompressor
from agent.model_metadata import MINIMUM_CONTEXT_LENGTH
from idea_foundry_agent.runtime import (
    DEFAULT_BASE_URL,
    DEFAULT_MODEL,
    DEFAULT_TOOLSETS,
    IdeaFoundryAgentRunner,
    LocalInferenceSettings,
    resolve_local_inference_settings,
)


def test_local_settings_default_to_local_openai_compatible_endpoint(monkeypatch):
    for name in (
        "HERMES_LOCAL_BASE_URL",
        "LOCAL_INFERENCE_BASE_URL",
        "LLAMA_SERVER_BASE_URL",
        "OPENAI_BASE_URL",
        "HERMES_LOCAL_MODEL",
        "LOCAL_INFERENCE_MODEL",
        "LLAMA_SERVER_MODEL",
        "MODEL",
        "HERMES_LOCAL_API_KEY",
        "LOCAL_INFERENCE_API_KEY",
        "LLAMA_SERVER_API_KEY",
        "OPENAI_API_KEY",
        "IDEA_FOUNDRY_AGENT_TOOLSETS",
        "IDEA_FOUNDRY_AGENT_MAX_ITERATIONS",
        "HERMES_TOOLSETS",
        "WEBAPP_AGENT_TOOLSETS",
    ):
        monkeypatch.delenv(name, raising=False)

    settings = resolve_local_inference_settings()

    assert DEFAULT_BASE_URL == "http://127.0.0.1:8080/v1"
    assert DEFAULT_MODEL == "gpt-3.5-turbo"
    assert settings.base_url == "http://127.0.0.1:8080/v1"
    assert settings.model == "gpt-3.5-turbo"
    assert settings.api_key == "local"
    assert DEFAULT_TOOLSETS == ("idea-foundry",)
    assert settings.toolsets == ("idea-foundry",)


def test_local_settings_accept_llama_server_overrides(monkeypatch):
    monkeypatch.setenv("LLAMA_SERVER_BASE_URL", "http://127.0.0.1:8080/v1")
    monkeypatch.setenv("LLAMA_SERVER_MODEL", "gpt-3.5-turbo")
    monkeypatch.setenv("LLAMA_SERVER_API_KEY", "sk-no-key-required")

    settings = resolve_local_inference_settings()

    assert settings.base_url == "http://127.0.0.1:8080/v1"
    assert settings.model == "gpt-3.5-turbo"
    assert settings.api_key == "sk-no-key-required"


def test_local_settings_accept_webapp_overrides(monkeypatch):
    monkeypatch.setenv("LOCAL_INFERENCE_BASE_URL", "http://localhost:8001/v1")
    monkeypatch.setenv("LOCAL_INFERENCE_MODEL", "qwen-local")
    monkeypatch.setenv("LOCAL_INFERENCE_API_KEY", "test-key")
    monkeypatch.setenv("IDEA_FOUNDRY_AGENT_TOOLSETS", "idea-foundry")

    settings = resolve_local_inference_settings()

    assert settings.base_url == "http://localhost:8001/v1"
    assert settings.model == "qwen-local"
    assert settings.api_key == "test-key"
    assert settings.toolsets == ("idea-foundry",)


def test_runner_builds_custom_provider_agent():
    captured = {}

    class FakeAgent:
        def __init__(self, **kwargs):
            captured.update(kwargs)
            self.session_id = kwargs["session_id"]

        def run_conversation(self, message, **kwargs):
            return {
                "final_response": f"echo: {message}",
                "completed": True,
                "api_calls": 1,
                "messages": [],
            }

    settings = LocalInferenceSettings(
        base_url="http://local.test/v1",
        model="local-model",
        api_key="local-key",
        toolsets=("idea-foundry",),
        max_iterations=7,
    )
    runner = IdeaFoundryAgentRunner(settings, agent_factory=FakeAgent)

    result = runner.run_cycle(
        "hello",
        rails_settings={"enabled": True, "destructive_actions_enabled": False},
        session_id="session-1",
    )

    assert result["final_response"] == "echo: hello"
    assert result["session_id"] == "session-1"
    assert captured["provider"] == "custom"
    assert captured["api_mode"] == "chat_completions"
    assert captured["enabled_toolsets"] == ["idea-foundry"]
    assert captured["platform"] == "idea_foundry"
    assert captured["load_soul_identity"] is False
    assert captured["skip_context_files"] is True
    assert captured["skip_memory"] is True


def test_runner_instantiates_the_real_agent_without_calling_a_model(monkeypatch, tmp_path):
    from run_agent import AIAgent

    monkeypatch.setenv("HERMES_HOME", str(tmp_path / "hermes"))
    settings = LocalInferenceSettings(
        base_url="http://127.0.0.1:8080/v1",
        model="local-test-model",
        api_key="local",
        toolsets=("idea-foundry",),
        max_iterations=3,
    )

    agent = IdeaFoundryAgentRunner(settings).create_agent(session_id="runtime-check")

    assert isinstance(agent, AIAgent)
    assert agent.provider == "custom"
    assert agent.base_url == settings.base_url
    assert agent.model == settings.model
    assert agent.platform == "idea_foundry"
    assert agent.session_id == "runtime-check"


def test_webapp_local_runtime_allows_small_context_window():
    app_local = SimpleNamespace(
        platform="idea_foundry",
        base_url="http://127.0.0.1:8080/v1",
    )
    cli_local = SimpleNamespace(
        platform="cli",
        base_url="http://127.0.0.1:8080/v1",
    )
    app_remote = SimpleNamespace(
        platform="idea_foundry",
        base_url="https://api.example.com/v1",
    )

    assert _requires_minimum_context(app_local, 32_768) is False
    assert _requires_minimum_context(cli_local, 32_768) is True
    assert _requires_minimum_context(app_remote, 32_768) is True
    assert _requires_minimum_context(cli_local, MINIMUM_CONTEXT_LENGTH) is False


def test_small_context_compressor_threshold_tracks_runtime_window(monkeypatch):
    monkeypatch.setattr(
        "agent.context_compressor.get_model_context_length",
        lambda *args, **kwargs: 32_768,
    )

    compressor = ContextCompressor(
        model="local-llama",
        base_url="http://127.0.0.1:8080/v1",
        provider="custom",
        quiet_mode=True,
    )

    assert compressor.context_length == 32_768
    assert compressor.threshold_tokens == 16_384

    compressor.update_model(
        model="larger-local",
        context_length=128_000,
        base_url="http://127.0.0.1:8080/v1",
        provider="custom",
    )

    assert compressor.threshold_tokens == 64_000


def test_skill_review_counter_tracks_tool_iterations_only():
    agent = SimpleNamespace(
        _skill_nudge_interval=1,
        _iters_since_skill=0,
        valid_tool_names={"skill_manage"},
    )

    _record_skill_review_iteration(agent)

    assert agent._iters_since_skill == 1


def test_skill_review_counter_ignores_disabled_skill_tool():
    agent = SimpleNamespace(
        _skill_nudge_interval=1,
        _iters_since_skill=0,
        valid_tool_names=set(),
    )

    _record_skill_review_iteration(agent)

    assert agent._iters_since_skill == 0
