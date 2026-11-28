#!/usr/bin/env python3
"""
browser.sh — browser-use adapter implementing the agent-browser CLI protocol.

Accepts agent-browser invocation style:
    browser.sh [--engine ENGINE] --session SESSION [--cdp CDP_URL] --json COMMAND [ARGS...]

Translates to browser-use CLI calls and emits agent-browser-compatible JSON.
Bundled so the idea-foundry-agent works without a separate Node/npm install.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


# ---------------------------------------------------------------------------
# Locating browser-use
# ---------------------------------------------------------------------------

def _find_browser_use() -> str:
    for name in ("browser-use", "bu"):
        found = shutil.which(name)
        if found:
            return found

    # Common virtualenv locations
    candidates = [
        Path.home() / ".browser-use-env" / "bin" / "browser-use",
        Path(sys.executable).parent / "browser-use",
        Path(sys.executable).parent / "bu",
    ]
    for c in candidates:
        if c.exists() and os.access(c, os.X_OK):
            return str(c)

    raise FileNotFoundError(
        "browser-use not found. Install with: pip install 'browser-use>=0.12'"
    )


# ---------------------------------------------------------------------------
# Protocol helpers
# ---------------------------------------------------------------------------

def _ref_to_index(ref: str) -> str:
    """Convert @e5 → '5' (or pass through plain integers)."""
    if ref.startswith("@e"):
        return ref[2:]
    return ref


def _translate_snapshot_text(text: str) -> str:
    """Replace [N] interactive-element markers with @eN refs."""
    return re.sub(r"\[(\d+)\]", r"[@e\1]", text)


def _call(bu: str, session: str, cdp_url: str | None,
          command: str, extra_args: list[str]) -> dict:
    """Invoke browser-use and return parsed JSON."""
    parts = [bu, "--session", session, "--json"]
    if cdp_url:
        parts += ["--cdp-url", cdp_url]
    parts += [command] + extra_args

    try:
        proc = subprocess.run(
            parts,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return {"success": False, "error": f"browser-use '{command}' timed out"}
    except Exception as exc:
        return {"success": False, "error": str(exc)}

    stdout = proc.stdout.strip()
    if stdout:
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            return {"success": False, "error": f"Non-JSON: {stdout[:400]}"}

    if proc.returncode != 0:
        err = proc.stderr.strip() or f"rc={proc.returncode}"
        return {"success": False, "error": err}

    return {"success": True, "data": {}}


# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------

def _dispatch(bu: str, session: str, cdp_url: str | None,
              command: str, cmd_args: list[str]) -> dict:

    if command == "snapshot":
        result = _call(bu, session, cdp_url, "state", [])
        if result.get("success"):
            raw = result.get("data", {}).get("_raw_text", "")
            return {"success": True, "data": {"snapshot": _translate_snapshot_text(raw)}}
        return result

    if command == "open":
        url = cmd_args[0] if cmd_args else ""
        return _call(bu, session, cdp_url, "open", [url])

    if command == "click":
        ref = cmd_args[0] if cmd_args else ""
        return _call(bu, session, cdp_url, "click", [_ref_to_index(ref)])

    if command == "fill":
        ref = cmd_args[0] if cmd_args else ""
        text = cmd_args[1] if len(cmd_args) > 1 else ""
        return _call(bu, session, cdp_url, "input", [_ref_to_index(ref), text])

    if command == "scroll":
        direction = cmd_args[0] if cmd_args else "down"
        return _call(bu, session, cdp_url, "scroll", [direction])

    if command == "back":
        return _call(bu, session, cdp_url, "back", [])

    if command == "press":
        key = cmd_args[0] if cmd_args else ""
        return _call(bu, session, cdp_url, "keys", [key])

    if command == "screenshot":
        tmp = os.path.join(tempfile.gettempdir(), f"browser-sh-{session}.png")
        result = _call(bu, session, cdp_url, "screenshot", [tmp])
        if result.get("success"):
            data = result.get("data", {})
            data.setdefault("path", tmp)
            return {"success": True, "data": data}
        return result

    if command in ("eval", "console"):
        expr = cmd_args[0] if cmd_args else ""
        return _call(bu, session, cdp_url, "eval", [expr])

    if command == "errors":
        return _call(bu, session, cdp_url, "eval",
                     ["JSON.stringify(window.__browserErrors||[])"])

    if command in ("close", "shutdown"):
        result = _call(bu, session, cdp_url, "close", [])
        return result if result.get("success") else {"success": True, "data": {}}

    # Unknown — pass through verbatim
    return _call(bu, session, cdp_url, command, cmd_args)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--session", default="default")
    parser.add_argument("--cdp", default=None)
    parser.add_argument("--engine", default=None)  # accepted, ignored
    parser.add_argument("--json", dest="as_json", action="store_true")
    parser.add_argument("command", nargs="?", default="")
    parser.add_argument("args", nargs="*")
    args = parser.parse_args()

    if not args.as_json:
        print("Error: --json required", file=sys.stderr)
        return 1

    try:
        bu = _find_browser_use()
    except FileNotFoundError as exc:
        print(json.dumps({"success": False, "error": str(exc)}))
        return 1

    result = _dispatch(bu, args.session, args.cdp, args.command, args.args)
    print(json.dumps(result))
    return 0 if result.get("success") else 1


if __name__ == "__main__":
    sys.exit(main())
