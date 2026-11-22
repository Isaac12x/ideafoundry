"""Idea Foundry adapter around the agent loop."""

from __future__ import annotations

import os
from dataclasses import dataclass, replace
from typing import Any, Callable

from idea_foundry_agent.prompts import (
    build_cycle_user_message,
    build_idea_foundry_system_prompt,
)


DEFAULT_BASE_URL = "http://127.0.0.1:8080/v1"
DEFAULT_MODEL = "gpt-3.5-turbo"
DEFAULT_API_KEY = "local"
DEFAULT_TOOLSETS = ("idea-foundry",)

AIAgent: Any = None


def _first_env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name, "").strip()
        if value:
            return value
    return default


def _parse_toolsets(value: str | None) -> tuple[str, ...]:
    if not value:
        return DEFAULT_TOOLSETS
    parsed = tuple(part.strip() for part in value.split(",") if part.strip())
    return parsed or DEFAULT_TOOLSETS


def _parse_int(value: str, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return parsed if parsed > 0 else default


@dataclass(frozen=True)
class LocalInferenceSettings:
    """Runtime settings for the local inference endpoint."""

    base_url: str = DEFAULT_BASE_URL
    model: str = DEFAULT_MODEL
    api_key: str = DEFAULT_API_KEY
    api_mode: str = "chat_completions"
    toolsets: tuple[str, ...] = DEFAULT_TOOLSETS
    max_iterations: int = 90


def resolve_local_inference_settings() -> LocalInferenceSettings:
    """Resolve local inference settings from the process environment."""

    return LocalInferenceSettings(
        base_url=_first_env(
            "LOCAL_INFERENCE_BASE_URL",
            "LLAMA_SERVER_BASE_URL",
            "OPENAI_BASE_URL",
            "HERMES_LOCAL_BASE_URL",
            default=DEFAULT_BASE_URL,
        ),
        model=_first_env(
            "LOCAL_INFERENCE_MODEL",
            "LLAMA_SERVER_MODEL",
            "MODEL",
            "HERMES_LOCAL_MODEL",
            default=DEFAULT_MODEL,
        ),
        api_key=_first_env(
            "LOCAL_INFERENCE_API_KEY",
            "LLAMA_SERVER_API_KEY",
            "OPENAI_API_KEY",
            "HERMES_LOCAL_API_KEY",
            default=DEFAULT_API_KEY,
        ),
        api_mode=_first_env(
            "LOCAL_INFERENCE_API_MODE",
            "HERMES_LOCAL_API_MODE",
            default="chat_completions",
        ),
        toolsets=_parse_toolsets(
            _first_env(
                "IDEA_FOUNDRY_AGENT_TOOLSETS",
                "WEBAPP_AGENT_TOOLSETS",
                "HERMES_TOOLSETS",
                default="",
            )
        ),
        max_iterations=_parse_int(
            _first_env(
                "IDEA_FOUNDRY_AGENT_MAX_ITERATIONS",
                "WEBAPP_AGENT_MAX_ITERATIONS",
                "HERMES_MAX_ITERATIONS",
                default="90",
            ),
            90,
        ),
    )


def _agent_class() -> type:
    global AIAgent
    if AIAgent is None:
        from run_agent import AIAgent as _AIAgent

        AIAgent = _AIAgent
    return AIAgent


class IdeaFoundryAgentRunner:
    """Creates a local-inference agent for Idea Foundry cycles."""

    def __init__(
        self,
        settings: LocalInferenceSettings | None = None,
        agent_factory: Callable[..., Any] | None = None,
    ) -> None:
        self.settings = settings or resolve_local_inference_settings()
        self._agent_factory = agent_factory

    def with_overrides(
        self,
        *,
        base_url: str | None = None,
        model: str | None = None,
        toolsets: tuple[str, ...] | None = None,
        max_iterations: int | None = None,
    ) -> "IdeaFoundryAgentRunner":
        settings = replace(
            self.settings,
            base_url=base_url or self.settings.base_url,
            model=model or self.settings.model,
            toolsets=toolsets or self.settings.toolsets,
            max_iterations=max_iterations or self.settings.max_iterations,
        )
        return IdeaFoundryAgentRunner(settings, agent_factory=self._agent_factory)

    def create_agent(self, *, session_id: str | None = None):
        factory = self._agent_factory or _agent_class()
        return factory(
            base_url=self.settings.base_url,
            api_key=self.settings.api_key,
            provider="custom",
            api_mode=self.settings.api_mode,
            model=self.settings.model,
            max_iterations=self.settings.max_iterations,
            enabled_toolsets=list(self.settings.toolsets),
            quiet_mode=True,
            platform="idea_foundry",
            session_id=session_id,
            load_soul_identity=False,
            skip_context_files=True,
            skip_memory=True,
        )

    def run_cycle(
        self,
        instructions: str | None = None,
        *,
        rails_settings: dict[str, Any] | None = None,
        conversation_history: list[dict[str, Any]] | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        agent = self.create_agent(session_id=session_id)
        result = agent.run_conversation(
            instructions or build_cycle_user_message(rails_settings),
            system_message=build_idea_foundry_system_prompt(rails_settings),
            conversation_history=conversation_history,
        )
        result.setdefault("session_id", getattr(agent, "session_id", session_id))
        return result

    def run_turn(
        self,
        message: str,
        *,
        system_message: str | None = None,
        conversation_history: list[dict[str, Any]] | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Backward-compatible one-shot call; new code should use run_cycle."""

        agent = self.create_agent(session_id=session_id)
        result = agent.run_conversation(
            message,
            system_message=system_message or build_idea_foundry_system_prompt(),
            conversation_history=conversation_history,
        )
        result.setdefault("session_id", getattr(agent, "session_id", session_id))
        return result
