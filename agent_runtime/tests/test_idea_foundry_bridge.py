from __future__ import annotations

from idea_foundry_agent.bridge import (
    DEFAULT_BRIDGE_URL,
    BridgeSettings,
    RailsToolBridge,
    resolve_bridge_settings,
)


class FakeResponse:
    status_code = 200
    text = '{"ok": true}'

    def json(self):
        return {"ok": True}


class FakeClient:
    def __init__(self):
        self.closed = False
        self.requests = []

    def post(self, url, json, headers):
        self.requests.append({"url": url, "json": json, "headers": headers})
        return FakeResponse()

    def close(self):
        self.closed = True


def test_bridge_posts_tool_call_to_rails_endpoint():
    fake = FakeClient()
    captured = {}

    def factory(timeout):
        captured["timeout"] = timeout
        return fake

    bridge = RailsToolBridge(
        BridgeSettings(
            base_url="http://rails.test/local_agent/tools",
            secret="secret",
            run_id="run-1",
            timeout_seconds=12,
        ),
        client_factory=factory,
    )

    result = bridge.call_tool("list_work", {"limit": 3})

    assert result == {"ok": True}
    assert captured["timeout"] == 12
    assert fake.closed is True
    assert fake.requests == [
        {
            "url": "http://rails.test/local_agent/tools/list_work",
            "json": {"limit": 3},
            "headers": {
                "accept": "application/json",
                "content-type": "application/json",
                "user-agent": "idea-foundry-agent/0.1",
                "x-idea-foundry-agent-secret": "secret",
                "x-idea-foundry-agent-run-id": "run-1",
            },
        }
    ]


def test_default_bridge_uses_caddy_hostname(monkeypatch):
    monkeypatch.delenv("IDEA_FOUNDRY_TOOL_BRIDGE_URL", raising=False)
    monkeypatch.delenv("IDEA_FOUNDRY_BRIDGE_URL", raising=False)
    monkeypatch.delenv("LOCAL_AGENT_TOOL_BRIDGE_URL", raising=False)
    monkeypatch.delenv("IDEA_FOUNDRY_RAILS_URL", raising=False)
    monkeypatch.delenv("LOCAL_AGENT_RAILS_URL", raising=False)

    settings = resolve_bridge_settings()

    assert DEFAULT_BRIDGE_URL == "https://ideas.local:8443/local-agent/tools"
    assert settings.base_url == "https://ideas.local:8443/local-agent/tools"


def test_bridge_derives_path_from_caddy_hostname(monkeypatch):
    monkeypatch.delenv("IDEA_FOUNDRY_TOOL_BRIDGE_URL", raising=False)
    monkeypatch.delenv("IDEA_FOUNDRY_BRIDGE_URL", raising=False)
    monkeypatch.delenv("LOCAL_AGENT_TOOL_BRIDGE_URL", raising=False)
    monkeypatch.setenv("IDEA_FOUNDRY_RAILS_URL", "https://ideas.local:8443")

    settings = resolve_bridge_settings()

    assert settings.base_url == "https://ideas.local:8443/local-agent/tools"


def test_bridge_normalizes_legacy_localhost_rails_url(monkeypatch):
    monkeypatch.delenv("IDEA_FOUNDRY_TOOL_BRIDGE_URL", raising=False)
    monkeypatch.delenv("IDEA_FOUNDRY_BRIDGE_URL", raising=False)
    monkeypatch.delenv("LOCAL_AGENT_TOOL_BRIDGE_URL", raising=False)
    monkeypatch.setenv("IDEA_FOUNDRY_RAILS_URL", "http://127.0.0.1:3000")

    settings = resolve_bridge_settings()

    assert settings.base_url == "https://ideas.local:8443/local-agent/tools"


def test_bridge_normalizes_legacy_localhost_tls_url(monkeypatch):
    monkeypatch.setenv(
        "IDEA_FOUNDRY_TOOL_BRIDGE_URL",
        "https://localhost:8443/local-agent/tools",
    )

    settings = resolve_bridge_settings()

    assert settings.base_url == "https://ideas.local:8443/local-agent/tools"


def test_bridge_uses_configured_ca_bundle(monkeypatch):
    monkeypatch.setenv("IDEA_FOUNDRY_BRIDGE_CA_BUNDLE", "/tmp/caddy-root.crt")

    settings = resolve_bridge_settings()

    assert settings.ca_bundle == "/tmp/caddy-root.crt"


def test_bridge_passes_ca_bundle_to_http_client():
    captured = {}

    def factory(**kwargs):
        captured.update(kwargs)
        return FakeClient()

    bridge = RailsToolBridge(
        BridgeSettings(
            base_url="https://ideas.local:8443/local-agent/tools",
            ca_bundle="/tmp/caddy-root.crt",
        ),
        client_factory=factory,
    )

    bridge.call_tool("get_settings", {})

    assert captured["verify"] == "/tmp/caddy-root.crt"
