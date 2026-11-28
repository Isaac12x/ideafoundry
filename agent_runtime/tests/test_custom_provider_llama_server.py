from __future__ import annotations

from agent.transports.chat_completions import ChatCompletionsTransport
from providers import get_provider_profile


def _custom_kwargs(**params):
    profile = get_provider_profile("custom")
    assert profile is not None
    return ChatCompletionsTransport().build_kwargs(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": "hello"}],
        provider_profile=profile,
        **params,
    )


def test_custom_provider_omits_ollama_options_for_llama_server():
    kwargs = _custom_kwargs(
        base_url="http://127.0.0.1:8080/v1",
        local_server_type="llamacpp",
        ollama_num_ctx=65536,
        reasoning_config={"enabled": False},
    )

    assert "extra_body" not in kwargs


def test_custom_provider_keeps_ollama_options_for_ollama_server():
    kwargs = _custom_kwargs(
        base_url="http://127.0.0.1:11434/v1",
        local_server_type="ollama",
        ollama_num_ctx=65536,
        reasoning_config={"enabled": False},
    )

    assert kwargs["extra_body"] == {
        "options": {"num_ctx": 65536},
        "think": False,
    }
