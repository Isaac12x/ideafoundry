from __future__ import annotations

from idea_foundry_agent.daemon import IdeaFoundryDaemon
from idea_foundry_agent.runtime import LocalInferenceSettings


class FakeBridge:
    def __init__(self, settings):
        self.settings = settings
        self.calls = []

    def call_tool(self, name, arguments):
        self.calls.append((name, arguments))
        if name == "get_settings":
            return {"settings": self.settings}
        return {"ok": True}


class FakeRunner:
    settings = LocalInferenceSettings(max_iterations=90)

    def __init__(self):
        self.overrides = {}
        self.run_kwargs = {}

    def with_overrides(self, **kwargs):
        self.overrides = kwargs
        return self

    def run_cycle(self, **kwargs):
        self.run_kwargs = kwargs
        return {
            "final_response": "done",
            "completed": True,
            "api_calls": 1,
            "messages": [{"role": "assistant", "content": "done"}],
        }


def test_daemon_run_once_exits_when_disabled():
    bridge = FakeBridge({"enabled": False})
    runner = FakeRunner()
    daemon = IdeaFoundryDaemon(bridge=bridge, runner=runner, session_id="sid")

    outcome = daemon.run_once()

    assert outcome.status == "disabled"
    assert runner.run_kwargs == {}
    assert bridge.calls == [("get_settings", {})]


def test_daemon_run_once_uses_rails_settings_and_records_heartbeats():
    settings = {
        "enabled": True,
        "destructive_actions_enabled": False,
        "model": "local-model",
        "base_url": "http://model.test/v1",
        "max_actions_per_cycle": 5,
    }
    bridge = FakeBridge(settings)
    runner = FakeRunner()
    daemon = IdeaFoundryDaemon(bridge=bridge, runner=runner, session_id="sid")

    outcome = daemon.run_once()

    assert outcome.status == "completed"
    assert runner.overrides == {
        "base_url": "http://model.test/v1",
        "model": "local-model",
        "max_iterations": 5,
    }
    assert runner.run_kwargs["rails_settings"] == settings
    assert runner.run_kwargs["session_id"] == "sid"
    assert daemon.conversation_history == [{"role": "assistant", "content": "done"}]
    assert [call[0] for call in bridge.calls] == [
        "get_settings",
        "record_event",
        "record_event",
    ]
