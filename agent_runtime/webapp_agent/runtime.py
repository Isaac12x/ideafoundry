"""Compatibility wrapper for the renamed Idea Foundry runtime."""

from idea_foundry_agent.runtime import (
    DEFAULT_API_KEY,
    DEFAULT_BASE_URL,
    DEFAULT_MODEL,
    DEFAULT_TOOLSETS,
    AIAgent,
    IdeaFoundryAgentRunner,
    LocalInferenceSettings,
    resolve_local_inference_settings,
)

WebappAgentRunner = IdeaFoundryAgentRunner

__all__ = [
    "AIAgent",
    "DEFAULT_API_KEY",
    "DEFAULT_BASE_URL",
    "DEFAULT_MODEL",
    "DEFAULT_TOOLSETS",
    "IdeaFoundryAgentRunner",
    "LocalInferenceSettings",
    "WebappAgentRunner",
    "resolve_local_inference_settings",
]
