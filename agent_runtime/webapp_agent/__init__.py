"""Compatibility package for the renamed Idea Foundry runtime."""

from idea_foundry_agent.runtime import (
    DEFAULT_TOOLSETS,
    IdeaFoundryAgentRunner,
    LocalInferenceSettings,
    resolve_local_inference_settings,
)

WebappAgentRunner = IdeaFoundryAgentRunner

__all__ = [
    "DEFAULT_TOOLSETS",
    "IdeaFoundryAgentRunner",
    "LocalInferenceSettings",
    "WebappAgentRunner",
    "resolve_local_inference_settings",
]
