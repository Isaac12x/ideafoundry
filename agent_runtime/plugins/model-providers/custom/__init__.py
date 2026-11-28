"""Custom OpenAI-compatible provider profile.

The custom profile covers local OpenAI-compatible endpoints such as
llama.cpp, vLLM, LM Studio, and Ollama. Only the Ollama route receives
Ollama-specific request body fields.
"""

from typing import Any

from providers import register_provider
from providers.base import ProviderProfile


class CustomProfile(ProviderProfile):
    """Custom local provider with Ollama-specific extras gated by server type."""

    @staticmethod
    def _is_ollama_route(base_url: Any = "", local_server_type: Any = None) -> bool:
        server_type = str(local_server_type or "").strip().lower()
        if server_type:
            return server_type == "ollama"

        normalized = str(base_url or "").strip().lower()
        return "ollama" in normalized or ":11434" in normalized

    def build_api_kwargs_extras(
        self,
        *,
        reasoning_config: dict | None = None,
        ollama_num_ctx: int | None = None,
        base_url: str | None = None,
        local_server_type: str | None = None,
        **ctx: Any,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        extra_body: dict[str, Any] = {}
        is_ollama = self._is_ollama_route(base_url, local_server_type)

        if is_ollama and ollama_num_ctx:
            options = extra_body.get("options", {})
            options["num_ctx"] = ollama_num_ctx
            extra_body["options"] = options

        if is_ollama and reasoning_config and isinstance(reasoning_config, dict):
            _effort = (reasoning_config.get("effort") or "").strip().lower()
            _enabled = reasoning_config.get("enabled", True)
            if _effort == "none" or _enabled is False:
                extra_body["think"] = False

        return extra_body, {}

    def fetch_models(
        self,
        *,
        api_key: str | None = None,
        timeout: float = 8.0,
    ) -> list[str] | None:
        """Custom/Ollama: base_url is user-configured; fetch if set."""
        if not self.base_url:
            return None
        return super().fetch_models(api_key=api_key, timeout=timeout)


custom = CustomProfile(
    name="custom",
    aliases=(
        "ollama",
        "local",
        "vllm",
        "llamacpp",
        "llama.cpp",
        "llama-cpp",
    ),
    env_vars=(),  # No fixed key — custom endpoint
    base_url="",  # User-configured
)

register_provider(custom)
