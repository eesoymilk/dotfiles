#!/usr/bin/env python3
"""Scan staged changes, branch commits, and draft text for traces of an AI session.

Prints one JSON object. Exits 1 when there are findings.
"""
# pyright: strict

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any, cast

AGENTS = r"claude|anthropic|opus|sonnet|haiku|fable|codex|openai|copilot|gemini|chatgpt"
RULES = {
    "attribution": rf"co-authored-by:.*\b({AGENTS}|cursor)\b"
    rf"|generated (with|by) .*\b({AGENTS}|cursor|ai)\b"
    r"|noreply@anthropic\.com|\U0001F916",
    "agent-authorship": r"\b(added|written|created|generated|fixed|updated|suggested|implemented"
    rf"|authored) by (the |an? )?({AGENTS}|ai|agent|assistant|llm)\b|\bas an ai\b",
    "decision-note": r"\bdeci(sion|ded)\b.*\b20\d\d-\d\d-\d\d\b"
    r"|\b20\d\d-\d\d-\d\d\b.*\bdeci(sion|ded)\b",
    "conversation": r"\bas (we )?discussed\b|\bper our (discussion|conversation|chat)\b"
    r"|\bper (the |your )?user('?s)? (request|ask|instructions?)\b"
    r"|\bper your (request|instructions?)\b|\bas (you |the user )?(requested|asked)\b(?! by)"
    r"|\bthe user (asked|requested|wanted|said)\b|\b(this|our) (conversation|chat)\b"
    r"|\bearlier in (the|this) (conversation|session)\b",
    "review-reference": r"\b(per|address|addressing) (the |a )?(pr |code )?review\b"
    r"|\b(from|after) (the |a )?(pr|code) review\b"
    r"|\bper (the )?reviewer\b|\breview(er)? (comment|feedback|asked|suggested)\b",
    "em-dash": chr(0x2014),
}
COMPILED = {name: re.compile(pattern, re.IGNORECASE) for name, pattern in RULES.items()}
HUNK = re.compile(r"^@@ -\S+ \+(\d+)")

# These files state the rules, so they contain the phrases on purpose.
EXEMPT_NAMES = {"AGENTS.md", "CLAUDE.md"}
EXEMPT_DIR = re.compile(r"(^|/)\.agents/skills/ship/")

Finding = dict[str, str]


def git(*args: str) -> str:
    out = subprocess.run(
        ["git", *args],
        check=False,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    if out.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def rules_matching(line: str) -> list[str]:
    return [name for name, pattern in COMPILED.items() if pattern.search(line)]


def is_exempt(path: str) -> bool:
    return Path(path).name in EXEMPT_NAMES or EXEMPT_DIR.search(path) is not None


def added_lines(diff: str) -> Iterator[tuple[str, int, str]]:
    """Yield (path, line number, text) for each added line of a unified diff."""
    path = ""
    number = 0
    in_header = False
    for line in diff.split("\n"):
        hunk = HUNK.match(line)
        if line.startswith("diff --git "):
            in_header = True
        elif in_header and line.startswith("+++ "):
            path = line[len("+++ b/") :].rstrip("\t")
        elif hunk:
            in_header = False
            number = int(hunk.group(1))
        elif not in_header and line.startswith("+"):
            yield path, number, line[1:]
            number += 1


def scan_diff(diff: str, prefix: str = "") -> list[Finding]:
    return [
        {"where": f"{prefix}{path}:{number}", "rule": rule, "line": text.strip()}
        for path, number, text in added_lines(diff)
        if not is_exempt(path)
        for rule in rules_matching(text)
    ]


def scan_text(text: str, where: str) -> list[Finding]:
    return [
        {"where": where, "rule": rule, "line": line.strip()}
        for line in text.split("\n")
        for rule in rules_matching(line)
    ]


def default_base() -> str:
    remotes = git("remote").split()
    for remote in ("upstream", "origin"):
        if remote in remotes:
            head = git("ls-remote", "--symref", remote, "HEAD")
            match = re.search(r"^ref: refs/heads/(\S+)\s+HEAD$", head, re.MULTILINE)
            if match:
                return f"{remote}/{match.group(1)}"
    raise RuntimeError("cannot find the default branch: pass --base")


def scan(base: str, draft: str | None) -> dict[str, Any]:
    diff_options = ("--no-color", "--no-ext-diff", "-U0", "--src-prefix=a/", "--dst-prefix=b/")
    staged = git("-c", "core.quotePath=false", "diff", "--cached", *diff_options, "HEAD")
    findings = scan_diff(staged)
    # Each commit is scanned on its own, because a trace removed by a later
    # commit is still in the history that gets pushed.
    for commit in git("rev-list", f"{base}..HEAD").split():
        where = f"commit {commit[:8]}"
        findings += scan_text(git("log", "-1", "--format=%B", commit), where)
        patch = git(
            "-c", "core.quotePath=false", "diff-tree", "-p", "--root", "--no-commit-id",
            *diff_options, commit,
        )  # fmt: skip
        findings += scan_diff(patch, f"{where} ")
    if draft is not None:
        findings += scan_text(draft, "draft text")
    return {"status": "traces" if findings else "clean", "base": base, "findings": findings}


def main() -> bool:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--base")
    parser.add_argument("--stdin", action="store_true", help="also scan draft text from stdin")
    args = parser.parse_args()
    base = cast("str | None", args.base) or default_base()
    draft = sys.stdin.read() if cast(bool, args.stdin) else None
    report = scan(base, draft)
    print(json.dumps(report))
    return report["status"] == "clean"


if __name__ == "__main__":
    try:
        sys.exit(0 if main() else 1)
    except Exception as e:  # noqa: BLE001
        print(json.dumps({"status": "error", "error": f"{type(e).__name__}: {e}"}))
        sys.exit(1)
