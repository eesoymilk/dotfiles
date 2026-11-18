from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest
from route import TIERS, Option, native_args, preferred, window_left

SCRIPT = Path(__file__).with_name("route.py")
NOW = 1_800_000_000


def test_native_args_follow_each_harness_flag_shape() -> None:
    assert native_args(Option("claude", "opus", "high")) == ["--model", "opus", "--effort", "high"]
    assert native_args(Option("codex", "gpt-6-luna", "low")) == [
        "--model",
        "gpt-6-luna",
        "-c",
        "model_reasoning_effort=low",
    ]
    assert native_args(Option("pi", "a/b", "off")) == ["--model", "a/b", "--thinking", "off"]
    assert native_args(Option("claude", "haiku")) == ["--model", "haiku"]


def test_native_args_reject_unknown_harnesses_and_efforts() -> None:
    with pytest.raises(ValueError, match="unsupported harness"):
        native_args(Option("gemini", "x"))
    with pytest.raises(ValueError, match="claude effort"):
        native_args(Option("claude", "opus", "ultra"))


def test_every_tier_option_is_launchable() -> None:
    for options in TIERS.values():
        for option in options:
            native_args(option)


def test_window_left_treats_a_past_reset_as_full() -> None:
    assert window_left(30.6, NOW + 60, NOW) == 70
    assert window_left(90, NOW - 60, NOW) == 100
    assert window_left(-1, 0, NOW) is None
    assert window_left(None, NOW + 60, NOW) is None
    assert window_left(120, 0, NOW) == 0


def test_preferred_needs_a_clear_gap() -> None:
    def usage(claude: int | None, codex: int | None) -> dict[str, dict[str, Any] | None]:
        return {
            "claude": None if claude is None else {"left": claude},
            "codex": None if codex is None else {"left": codex},
        }

    assert preferred(usage(90, 50)) == "claude"
    assert preferred(usage(30, 60)) == "codex"
    assert preferred(usage(70, 60)) is None
    assert preferred(usage(None, 60)) is None


def run_status(home: Path) -> dict[str, Any]:
    out = subprocess.run(
        [sys.executable, "-B", str(SCRIPT), "status"],
        env={
            "PATH": os.environ["PATH"],
            "HOME": str(home),
            "XDG_CACHE_HOME": str(home / "cache"),
            "CODEX_HOME": str(home / "codex"),
        },
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def test_status_reads_both_harnesses_quota(tmp_path: Path) -> None:
    cache = tmp_path / "cache/claude"
    cache.mkdir(parents=True)
    far = 4_000_000_000
    (cache / "rate-limits.json").write_text(
        json.dumps(
            {
                "five_hour": {"used_percent": 10, "resets_at": far},
                "seven_day": {"used_percent": 75, "resets_at": far},
                "updated_at": 0,
            }
        )
    )
    day = tmp_path / "codex/sessions/2026/11/11"
    day.mkdir(parents=True)
    limits = {
        "primary": {"used_percent": 40.0, "window_minutes": 300, "resets_at": far},
        "secondary": {"used_percent": 5.0, "window_minutes": 10080, "resets_at": far},
    }

    def record(stamp: str, rate_limits: dict[str, Any] | None) -> str:
        return json.dumps({"timestamp": stamp, "payload": {"rate_limits": rate_limits}}) + "\n"

    stale = {**limits, "secondary": {**limits["secondary"], "used_percent": 1.0}}
    (day / "current.jsonl").write_text(
        record("2026-11-11T10:00:00.000Z", limits) + record("2026-11-11T10:05:00.000Z", None)
    )
    # An older session resumed later: the newest file, holding an older record.
    resumed = day / "resumed.jsonl"
    resumed.write_text(record("2026-11-08T10:00:00.000Z", stale))
    os.utime(resumed, (far, far))
    out = run_status(tmp_path)
    assert out["usage"]["claude"]["left"] == 25
    codex = out["usage"]["codex"]
    assert (codex["five_hour_left"], codex["seven_day_left"], codex["left"]) == (60, 95, 60)
    assert out["prefer"] == "codex"
    assert out["tiers"]["normal"][1]["args"][:2] == ["--model", "gpt-6.1-sol"]


def test_status_without_quota_data_prefers_nothing(tmp_path: Path) -> None:
    out = run_status(tmp_path)
    assert out["usage"] == {"claude": None, "codex": None}
    assert out["prefer"] is None


def test_status_survives_a_malformed_claude_cache(tmp_path: Path) -> None:
    cache = tmp_path / "cache/claude"
    cache.mkdir(parents=True)
    path = cache / "rate-limits.json"
    path.write_text(json.dumps({"five_hour": None, "seven_day": {"used_percent": 30}}))
    assert run_status(tmp_path)["usage"]["claude"]["left"] == 70
    path.write_text("[]")
    assert run_status(tmp_path)["usage"]["claude"] is None


def test_args_command_reports_bad_effort_as_json() -> None:
    out = subprocess.run(
        [
            sys.executable,
            "-B",
            str(SCRIPT),
            "args",
            "--kind",
            "codex",
            "--model",
            "m",
            "--effort",
            "x",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert out.returncode == 1
    assert "codex effort" in json.loads(out.stdout)["error"]
