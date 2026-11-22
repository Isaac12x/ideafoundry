"""HTTP bridge from local agent tools to the Rails control plane."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlsplit, urlunsplit

import httpx


DEFAULT_RAILS_URL = "https://ideas.local:8443"
DEFAULT_BRIDGE_PATH = "/local-agent/tools"
DEFAULT_BRIDGE_URL = f"{DEFAULT_RAILS_URL}{DEFAULT_BRIDGE_PATH}"
DEFAULT_TIMEOUT_SECONDS = 30.0
CADDY_LOCAL_CA_PATHS = (
    Path("~/Library/Application Support/Caddy/pki/authorities/local/root.crt"),
    Path("~/.local/share/caddy/pki/authorities/local/root.crt"),
    Path("~/snap/caddy/common/.local/share/caddy/pki/authorities/local/root.crt"),
)


class BridgeError(RuntimeError):
    """Raised when the Rails local-agent bridge cannot complete a tool call."""


def _first_env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name, "").strip()
        if value:
            return value
    return default


def _parse_float(value: str, default: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    return parsed if parsed > 0 else default


def _bridge_url_from_rails_url(rails_url: str) -> str:
    return f"{rails_url.rstrip('/')}{DEFAULT_BRIDGE_PATH}"


def _uses_legacy_localhost_target(url: str) -> bool:
    parsed = urlsplit(url)
    hostname = parsed.hostname or ""
    try:
        port = parsed.port
    except ValueError:
        return False
    return hostname in {"localhost", "127.0.0.1"} and port in {3000, 8443}


def _replace_with_caddy_hostname(url: str) -> str:
    parsed = urlsplit(url)
    default = urlsplit(DEFAULT_RAILS_URL)
    netloc = default.netloc
    if parsed.username or parsed.password:
        userinfo = parsed.username or ""
        if parsed.password:
            userinfo = f"{userinfo}:{parsed.password}"
        netloc = f"{userinfo}@{netloc}"
    return urlunsplit((default.scheme, netloc, parsed.path, parsed.query, parsed.fragment))


def _normalize_local_bridge_url(url: str) -> str:
    if _uses_legacy_localhost_target(url):
        return _replace_with_caddy_hostname(url)
    return url


def _is_default_caddy_host(url: str) -> bool:
    parsed = urlsplit(url)
    return parsed.hostname == "ideas.local"


def _default_caddy_ca_bundle() -> str:
    for path in CADDY_LOCAL_CA_PATHS:
        expanded = path.expanduser()
        if expanded.is_file():
            return str(expanded)
    return ""


def _resolve_ca_bundle(base_url: str) -> str:
    configured = _first_env(
        "IDEA_FOUNDRY_BRIDGE_CA_BUNDLE",
        "LOCAL_AGENT_BRIDGE_CA_BUNDLE",
        default="",
    )
    if configured:
        return configured
    if _is_default_caddy_host(base_url):
        return _default_caddy_ca_bundle()
    return ""


@dataclass(frozen=True)
class BridgeSettings:
    """Settings for the private Rails local-agent tool bridge."""

    base_url: str = DEFAULT_BRIDGE_URL
    secret: str = ""
    run_id: str = ""
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
    ca_bundle: str = ""


def resolve_bridge_settings() -> BridgeSettings:
    """Resolve bridge settings from process environment."""

    explicit_bridge_url = _first_env(
        "IDEA_FOUNDRY_TOOL_BRIDGE_URL",
        "IDEA_FOUNDRY_BRIDGE_URL",
        "LOCAL_AGENT_TOOL_BRIDGE_URL",
        default="",
    )
    rails_url = _first_env(
        "IDEA_FOUNDRY_RAILS_URL",
        "LOCAL_AGENT_RAILS_URL",
        default=DEFAULT_RAILS_URL,
    )

    base_url = _normalize_local_bridge_url(
        explicit_bridge_url or _bridge_url_from_rails_url(rails_url)
    )

    return BridgeSettings(
        base_url=base_url,
        secret=_first_env(
            "IDEA_FOUNDRY_AGENT_SECRET",
            "LOCAL_AGENT_SECRET",
            default="",
        ),
        run_id=_first_env(
            "IDEA_FOUNDRY_AGENT_RUN_ID",
            "LOCAL_AGENT_RUN_ID",
            default="",
        ),
        timeout_seconds=_parse_float(
            _first_env("IDEA_FOUNDRY_BRIDGE_TIMEOUT", default="30"),
            DEFAULT_TIMEOUT_SECONDS,
        ),
        ca_bundle=_resolve_ca_bundle(base_url),
    )


class RailsToolBridge:
    """Client for Rails-owned Idea Foundry domain tools.

    The agent never mutates Rails data directly. Each tool call is posted to the
    local Rails bridge, where ownership, settings, locking, history, and audit
    rules are enforced.
    """

    def __init__(
        self,
        settings: BridgeSettings | None = None,
        client_factory: Callable[..., Any] | None = None,
    ) -> None:
        self.settings = settings or resolve_bridge_settings()
        self._client_factory = client_factory or httpx.Client

    def _url_for(self, tool_name: str) -> str:
        return f"{self.settings.base_url.rstrip('/')}/{tool_name}"

    def _headers(self) -> dict[str, str]:
        headers = {
            "accept": "application/json",
            "content-type": "application/json",
            "user-agent": "idea-foundry-agent/0.1",
        }
        if self.settings.secret:
            headers["x-idea-foundry-agent-secret"] = self.settings.secret
        if self.settings.run_id:
            headers["x-idea-foundry-agent-run-id"] = self.settings.run_id
        return headers

    def _client_kwargs(self) -> dict[str, Any]:
        kwargs: dict[str, Any] = {"timeout": self.settings.timeout_seconds}
        if self.settings.ca_bundle:
            kwargs["verify"] = self.settings.ca_bundle
        return kwargs

    def call_tool(self, tool_name: str, arguments: dict[str, Any] | None = None) -> Any:
        """Call a Rails domain tool and return decoded JSON."""

        payload = arguments or {}
        client = self._client_factory(**self._client_kwargs())
        try:
            response = client.post(
                self._url_for(tool_name),
                json=payload,
                headers=self._headers(),
            )
        except httpx.RequestError as exc:
            raise BridgeError(f"Bridge request failed for {tool_name}: {exc}") from exc
        finally:
            close = getattr(client, "close", None)
            if callable(close):
                close()

        text = getattr(response, "text", "")
        status_code = int(getattr(response, "status_code", 0) or 0)
        if status_code >= 400:
            detail = self._decode_response(response)
            raise BridgeError(
                f"Rails bridge rejected {tool_name} with HTTP {status_code}: {detail}"
            )

        decoded = self._decode_response(response)
        return decoded if decoded is not None else {"ok": True, "body": text}

    def call_tool_json(
        self, tool_name: str, arguments: dict[str, Any] | None = None
    ) -> str:
        """Call a Rails tool and serialize the result for the model loop."""

        try:
            return json.dumps(self.call_tool(tool_name, arguments), ensure_ascii=True)
        except BridgeError as exc:
            return json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=True)

    @staticmethod
    def _decode_response(response: Any) -> Any:
        try:
            return response.json()
        except (TypeError, ValueError, json.JSONDecodeError):
            return getattr(response, "text", None)
