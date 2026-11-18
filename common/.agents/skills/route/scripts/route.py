#!/usr/bin/env python3
"""Pick a harness, model, and effort for a delegated agent.

`status` prints the tier table, each option's native launch arguments, and the
quota left on Claude Code and Codex. `args` prints the native launch arguments
for a harness, model, and effort chosen by hand. Both print one JSON object.
"""
# pyright: strict

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, NamedTuple, cast


class Option(NamedTuple):
    kind: str
    model: str
    effort: str | None = None


LOCAL_MODEL = "llama.cpp/qwen3.8-27b"
LOCAL_SERVER = "http://127.0.0.1:8081/v1/models"

# Ordered from the most to the least capable. Within a tier, the options are
# interchangeable and the choice between them follows the quota left.
TIERS: dict[str, list[Option]] = {
    "max": [Option("claude", "fable", "high"), Option("codex", "gpt-6-astra", "high")],
    "normal": [Option("claude", "opus", "medium"), Option("codex", "gpt-6.1-sol", "medium")],
    "easy": [Option("claude", "sonnet", "medium"), Option("codex", "gpt-6-luna", "medium")],
    "light": [Option("claude", "haiku")],
    "trivial": [Option("pi", LOCAL_MODEL)],
}

EFFORTS = {
    "claude": ("low", "medium", "high", "xhigh", "max"),
    "codex": ("low", "medium", "high", "xhigh", "max", "ultra"),
    "pi": ("off", "minimal", "low", "medium", "high", "xhigh", "max"),
}

# Below this many points of difference in quota left, neither harness is preferred.
PREFER_GAP = 20
WINDOWS = {300: "five_hour", 10080: "seven_day"}
CODEX_LOGS_SCANNED = 50


def native_args(option: Option) -> list[str]:
    kind, model, effort = option
    if kind not in EFFORTS:
        raise ValueError(f"unsupported harness {kind!r}: use one of {', '.join(EFFORTS)}")
    if effort is not None and effort not in EFFORTS[kind]:
        raise ValueError(f"{kind} effort must be one of {', '.join(EFFORTS[kind])}")
    args = ["--model", model]
    if effort is None:
        return args
    if kind == "codex":
        return [*args, "-c", f"model_reasoning_effort={effort}"]
    return [*args, "--thinking" if kind == "pi" else "--effort", effort]


def window_left(used: Any, resets_at: Any, now: float) -> int | None:
    """Percent left in a window, or None when unknown. A window past its reset is full."""
    if not isinstance(used, (int, float)) or used < 0:
        return None
    if isinstance(resets_at, (int, float)) and 0 < resets_at <= now:
        return 100
    return max(0, 100 - int(used))


def summarize(windows: dict[str, int | None], as_of: float, now: float) -> dict[str, Any]:
    known = [v for v in windows.values() if v is not None]
    return {
        **{f"{name}_left": left for name, left in windows.items()},
        "left": min(known) if known else None,
        "age_minutes": int((now - as_of) // 60),
    }


def claude_usage(now: float) -> dict[str, Any] | None:
    """Read the rate limits the Claude Code status line caches on every render."""
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    try:
        data: Any = json.loads((cache / "claude/rate-limits.json").read_text())
        updated_at = float(data.get("updated_at", 0))
    except (OSError, ValueError, TypeError, AttributeError):
        return None
    windows: dict[str, int | None] = {}
    for name in WINDOWS.values():
        window = data.get(name)
        if not isinstance(window, dict):
            windows[name] = None
            continue
        window = cast("dict[str, Any]", window)
        windows[name] = window_left(window.get("used_percent"), window.get("resets_at"), now)
    return summarize(windows, updated_at, now)


def last_rate_limits(log: Path) -> tuple[float, dict[str, Any]] | None:
    """The newest rate limit record in a Codex session log, with its timestamp."""
    try:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        if '"rate_limits"' not in line:
            continue
        try:
            record = json.loads(line)
            stamp = datetime.fromisoformat(str(record["timestamp"]).replace("Z", "+00:00"))
        except (ValueError, KeyError):
            continue
        limits = record.get("payload", {}).get("rate_limits")
        if isinstance(limits, dict) and limits.get("primary"):
            return stamp.timestamp(), cast("dict[str, Any]", limits)
    return None


def codex_usage(now: float) -> dict[str, Any] | None:
    """Read the newest rate limits Codex logged with a turn in any session."""
    sessions = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "sessions"
    logs: list[tuple[float, Path]] = []
    for log in sessions.glob("*/*/*/*.jsonl"):
        try:
            logs.append((log.stat().st_mtime, log))
        except OSError:
            continue  # removed after the glob listed it
    logs.sort(reverse=True)
    newest: tuple[float, dict[str, Any]] | None = None
    # A resumed session appends to an old file, so the newest file need not hold
    # the newest record; but a file last written before the best record so far
    # cannot hold a newer one.
    for mtime, log in logs[:CODEX_LOGS_SCANNED]:
        if newest and mtime < newest[0]:
            break
        found = last_rate_limits(log)
        if found and (newest is None or found[0] > newest[0]):
            newest = found
    if newest is None:
        return None
    as_of, limits = newest
    windows: dict[str, int | None] = dict.fromkeys(WINDOWS.values())
    for key in ("primary", "secondary"):
        window = limits.get(key) or {}
        name = WINDOWS.get(window.get("window_minutes"))
        if name:
            windows[name] = window_left(window.get("used_percent"), window.get("resets_at"), now)
    return summarize(windows, as_of, now)


def preferred(usage: dict[str, dict[str, Any] | None]) -> str | None:
    claude, codex = (u["left"] if u else None for u in (usage["claude"], usage["codex"]))
    if claude is None or codex is None or abs(claude - codex) < PREFER_GAP:
        return None
    return "claude" if claude > codex else "codex"


def local_server_up() -> bool:
    try:
        with urllib.request.urlopen(LOCAL_SERVER, timeout=2) as response:
            return cast(int, response.status) == 200
    except OSError:
        return False


def status() -> dict[str, Any]:
    now = time.time()
    usage = {"claude": claude_usage(now), "codex": codex_usage(now)}
    local_up = local_server_up()

    def describe(option: Option) -> dict[str, Any]:
        available = shutil.which(option.kind) is not None
        if option.model == LOCAL_MODEL:
            available = available and local_up
        return {**option._asdict(), "args": native_args(option), "available": available}

    return {
        "usage": usage,
        "prefer": preferred(usage),
        "tiers": {tier: [describe(o) for o in options] for tier, options in TIERS.items()},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    chosen = commands.add_parser("args")
    chosen.add_argument("--kind", required=True, choices=sorted(EFFORTS))
    chosen.add_argument("--model", required=True)
    chosen.add_argument("--effort")
    args = parser.parse_args()
    if args.command == "status":
        print(json.dumps(status()))
        return
    option = Option(cast(str, args.kind), cast(str, args.model), cast("str | None", args.effort))
    print(json.dumps({"kind": option.kind, "args": native_args(option)}))


if __name__ == "__main__":
    try:
        main()
    except ValueError as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
