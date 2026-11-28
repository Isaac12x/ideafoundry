"""Continuous Idea Foundry local-agent daemon."""

from __future__ import annotations

import argparse
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from threading import Event
from typing import Any, Callable

from idea_foundry_agent.bridge import BridgeError, RailsToolBridge
from idea_foundry_agent.runtime import IdeaFoundryAgentRunner


logger = logging.getLogger(__name__)


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _positive_int(value: Any, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return parsed if parsed > 0 else default


def _trim_history(
    messages: list[dict[str, Any]],
    limit: int = 60,
) -> list[dict[str, Any]]:
    if len(messages) <= limit:
        return messages
    return messages[-limit:]


@dataclass
class CycleOutcome:
    """Result of one daemon cycle."""

    status: str
    settings: dict[str, Any] = field(default_factory=dict)
    result: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


class IdeaFoundryDaemon:
    """Runs autonomous Idea Foundry cycles while Rails settings allow it."""

    def __init__(
        self,
        *,
        runner: IdeaFoundryAgentRunner | None = None,
        bridge: RailsToolBridge | None = None,
        sleep_fn: Callable[[float], None] = time.sleep,
        session_id: str | None = None,
    ) -> None:
        self.runner = runner or IdeaFoundryAgentRunner()
        self.bridge = bridge or RailsToolBridge()
        self.sleep_fn = sleep_fn
        self.session_id = session_id or os.getenv(
            "IDEA_FOUNDRY_AGENT_SESSION_ID",
            f"idea-foundry-{uuid.uuid4()}",
        )
        self.conversation_history: list[dict[str, Any]] = []

    def fetch_settings(self) -> dict[str, Any]:
        raw = self.bridge.call_tool("get_settings", {})
        if isinstance(raw, dict) and isinstance(raw.get("settings"), dict):
            return raw["settings"]
        return raw if isinstance(raw, dict) else {}

    def run_once(self) -> CycleOutcome:
        settings = self.fetch_settings()
        if not _truthy(settings.get("enabled")):
            return CycleOutcome(status="disabled", settings=settings)

        max_actions = _positive_int(
            settings.get("max_actions_per_cycle"),
            self.runner.settings.max_iterations,
        )
        runner = self.runner.with_overrides(
            base_url=settings.get("base_url") or None,
            model=settings.get("model") or None,
            max_iterations=max_actions,
        )

        self._record_event(
            "heartbeat",
            "Idea Foundry local agent cycle started.",
            {"session_id": self.session_id},
        )
        result = runner.run_cycle(
            rails_settings=settings,
            conversation_history=self.conversation_history,
            session_id=self.session_id,
        )
        messages = result.get("messages")
        if isinstance(messages, list):
            self.conversation_history = _trim_history(messages)

        self._record_event(
            "heartbeat",
            "Idea Foundry local agent cycle completed.",
            {
                "session_id": self.session_id,
                "completed": bool(result.get("completed")),
                "api_calls": int(result.get("api_calls") or 0),
            },
        )
        return CycleOutcome(status="completed", settings=settings, result=result)

    def run_forever(
        self,
        *,
        stop_event: Event | None = None,
        max_cycles: int | None = None,
        sleep_seconds_override: int | None = None,
    ) -> None:
        stop_event = stop_event or Event()
        cycles = 0
        consecutive_errors = 0

        while not stop_event.is_set():
            if max_cycles is not None and cycles >= max_cycles:
                return
            try:
                outcome = self.run_once()
            except BridgeError as exc:
                consecutive_errors += 1
                delay = min(300, 2 ** min(consecutive_errors, 8))
                logger.warning("Idea Foundry bridge error: %s", exc)
                self.sleep_fn(delay)
                continue
            except Exception as exc:
                consecutive_errors += 1
                delay = min(300, 2 ** min(consecutive_errors, 8))
                logger.exception("Idea Foundry daemon cycle failed")
                self._record_event(
                    "error",
                    "Idea Foundry local agent cycle failed.",
                    {"error": f"{type(exc).__name__}: {exc}"},
                )
                self.sleep_fn(delay)
                continue

            consecutive_errors = 0
            cycles += 1
            if outcome.status == "disabled":
                logger.info("Idea Foundry local agent disabled; exiting")
                return

            sleep_seconds = sleep_seconds_override
            if sleep_seconds is None:
                sleep_seconds = _positive_int(
                    outcome.settings.get("sleep_seconds"),
                    30,
                )
            self.sleep_fn(sleep_seconds)

    def _record_event(
        self, event_type: str, summary: str, payload: dict[str, Any] | None = None
    ) -> None:
        try:
            self.bridge.call_tool(
                "record_event",
                {
                    "event_type": event_type,
                    "summary": summary,
                    "payload": payload or {},
                },
            )
        except Exception as exc:
            logger.debug("Could not record Idea Foundry event: %s", exc)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the Idea Foundry local agent.")
    parser.add_argument("--once", action="store_true", help="Run one cycle and exit.")
    parser.add_argument(
        "--max-cycles",
        type=int,
        default=None,
        help="Stop after this many enabled cycles.",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=int,
        default=None,
        help="Override Rails sleep_seconds between cycles.",
    )
    parser.add_argument(
        "--run-id",
        default=None,
        help="Rails AgentRun id to send back to the tool bridge.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose daemon logging.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.run_id:
        os.environ["IDEA_FOUNDRY_AGENT_RUN_ID"] = args.run_id

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    daemon = IdeaFoundryDaemon()
    run_once = args.once or _truthy(os.getenv("IDEA_FOUNDRY_AGENT_RUN_ONCE"))
    if run_once:
        try:
            outcome = daemon.run_once()
        except Exception as exc:
            logger.error("Cycle failed: %s", exc)
            return 1
        logger.info("Cycle status: %s", outcome.status)
        return 0

    daemon.run_forever(
        max_cycles=args.max_cycles,
        sleep_seconds_override=args.sleep_seconds,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
