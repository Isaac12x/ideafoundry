"""FastAPI surface for Idea Foundry local-agent cycles."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field

from idea_foundry_agent.runtime import DEFAULT_TOOLSETS, IdeaFoundryAgentRunner


app = FastAPI(title="Idea Foundry Agent", version="0.1.0")


class AgentCycleRequest(BaseModel):
    """One Idea Foundry-driven agent cycle."""

    instructions: str | None = None
    rails_settings: dict[str, Any] | None = None
    conversation_history: list[dict[str, Any]] = Field(default_factory=list)
    session_id: str | None = None
    model: str | None = None
    toolsets: list[str] | None = None
    max_iterations: int | None = Field(default=None, gt=0)


class AgentCycleResponse(BaseModel):
    """Compact response shape for app clients."""

    final_response: str
    completed: bool
    api_calls: int
    session_id: str | None = None
    messages: list[dict[str, Any]] = Field(default_factory=list)


class AgentTurnRequest(BaseModel):
    """Deprecated compatibility shape for old webapp callers."""

    message: str = Field(min_length=1)
    system_message: str | None = None
    conversation_history: list[dict[str, Any]] = Field(default_factory=list)
    session_id: str | None = None
    model: str | None = None
    toolsets: list[str] | None = None
    max_iterations: int | None = Field(default=None, gt=0)


AgentTurnResponse = AgentCycleResponse


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "default_toolsets": list(DEFAULT_TOOLSETS)}


def _runner_with_request_overrides(
    runner: IdeaFoundryAgentRunner,
    *,
    model: str | None,
    toolsets: list[str] | None,
    max_iterations: int | None,
) -> IdeaFoundryAgentRunner:
    toolset_tuple = tuple(toolsets) if toolsets else None
    if model or toolset_tuple or max_iterations:
        return runner.with_overrides(
            model=model,
            toolsets=toolset_tuple,
            max_iterations=max_iterations,
        )
    return runner


def _compact_response(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "final_response": result.get("final_response") or "",
        "completed": bool(result.get("completed")),
        "api_calls": int(result.get("api_calls") or 0),
        "session_id": result.get("session_id"),
        "messages": result.get("messages") or [],
    }


@app.post("/api/agent/cycle", response_model=AgentCycleResponse)
def run_agent_cycle(request: AgentCycleRequest) -> dict[str, Any]:
    runner = _runner_with_request_overrides(
        IdeaFoundryAgentRunner(),
        model=request.model,
        toolsets=request.toolsets,
        max_iterations=request.max_iterations,
    )
    result = runner.run_cycle(
        request.instructions,
        rails_settings=request.rails_settings,
        conversation_history=request.conversation_history,
        session_id=request.session_id,
    )
    return _compact_response(result)


@app.post("/api/agent/turn", response_model=AgentTurnResponse)
def run_agent_turn(request: AgentTurnRequest) -> dict[str, Any]:
    runner = _runner_with_request_overrides(
        IdeaFoundryAgentRunner(),
        model=request.model,
        toolsets=request.toolsets,
        max_iterations=request.max_iterations,
    )
    result = runner.run_turn(
        request.message,
        system_message=request.system_message,
        conversation_history=request.conversation_history,
        session_id=request.session_id,
    )
    return _compact_response(result)
