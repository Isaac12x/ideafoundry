"""Compatibility wrapper for the renamed Idea Foundry API."""

from idea_foundry_agent.api import (
    AgentCycleRequest,
    AgentCycleResponse,
    AgentTurnRequest,
    AgentTurnResponse,
    app,
    health,
    run_agent_cycle,
    run_agent_turn,
)
from idea_foundry_agent.runtime import IdeaFoundryAgentRunner

WebappAgentRunner = IdeaFoundryAgentRunner

__all__ = [
    "AgentCycleRequest",
    "AgentCycleResponse",
    "AgentTurnRequest",
    "AgentTurnResponse",
    "IdeaFoundryAgentRunner",
    "WebappAgentRunner",
    "app",
    "health",
    "run_agent_cycle",
    "run_agent_turn",
]
