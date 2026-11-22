from __future__ import annotations

from fastapi.testclient import TestClient

import idea_foundry_agent.api as api


def test_agent_cycle_endpoint_returns_compact_response(monkeypatch):
    class FakeRunner:
        def with_overrides(self, **kwargs):
            self.overrides = kwargs
            return self

        def run_cycle(self, instructions=None, **kwargs):
            return {
                "final_response": f"handled {instructions}",
                "completed": True,
                "api_calls": 2,
                "session_id": kwargs["session_id"],
                "messages": [{"role": "assistant", "content": "handled"}],
            }

    monkeypatch.setattr(api, "IdeaFoundryAgentRunner", lambda: FakeRunner())
    client = TestClient(api.app)

    response = client.post(
        "/api/agent/cycle",
        json={"instructions": "build", "session_id": "abc", "model": "local"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "final_response": "handled build",
        "completed": True,
        "api_calls": 2,
        "session_id": "abc",
        "messages": [{"role": "assistant", "content": "handled"}],
    }


def test_deprecated_turn_endpoint_still_works(monkeypatch):
    class FakeRunner:
        def with_overrides(self, **kwargs):
            return self

        def run_turn(self, message, **kwargs):
            return {
                "final_response": f"turn {message}",
                "completed": True,
                "api_calls": 1,
                "session_id": kwargs["session_id"],
                "messages": [],
            }

    monkeypatch.setattr(api, "IdeaFoundryAgentRunner", lambda: FakeRunner())
    client = TestClient(api.app)

    response = client.post(
        "/api/agent/turn",
        json={"message": "build", "session_id": "abc"},
    )

    assert response.status_code == 200
    assert response.json()["final_response"] == "turn build"
