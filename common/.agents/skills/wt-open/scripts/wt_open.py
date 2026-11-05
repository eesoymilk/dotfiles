#!/usr/bin/env python3
"""Open a git worktree as a herdr workspace and brief a new agent in it.

The briefing comes from stdin. Prints one JSON object describing the outcome.
"""
# pyright: strict

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, NamedTuple, cast

ENV_FILE = re.compile(
    r"(^|/)\.env($|\.)|(^|/)\.dev\.vars$|\.local\.(toml|json|ya?ml)$|(^|/)\.envrc$"
)
MAX_AGENT_NAME = 32


class Result(NamedTuple):
    ok: bool
    stdout: str
    stderr: str

    @property
    def message(self) -> str:
        return self.stderr or self.stdout


def run(*cmd: str) -> Result:
    out = subprocess.run(
        cmd,
        check=False,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    return Result(out.returncode == 0, out.stdout.rstrip(), out.stderr.strip())


def must(*cmd: str) -> str:
    result = run(*cmd)
    if not result.ok:
        raise RuntimeError(f"{' '.join(cmd)}: {result.message}")
    return result.stdout


def must_json(*cmd: str) -> dict[str, Any]:
    return cast("dict[str, Any]", json.loads(must(*cmd)))


def emit(report: dict[str, Any]) -> None:
    print(json.dumps(report))


def is_env_file(path: str) -> bool:
    return not path.endswith("/") and ENV_FILE.search(path) is not None


def agent_slug(text: str) -> str:
    """Reduce text to a valid herdr agent name: `[a-z][a-z0-9_-]{0,31}`."""
    slug = re.sub(r"[^a-z0-9_-]+", "-", text.lower())
    slug = re.sub(r"^[^a-z]+", "", slug)
    return re.sub(r"[-_]+$", "", (slug or "wt")[:MAX_AGENT_NAME])


def slug_from_branch(branch: str) -> str:
    return agent_slug(branch.split("/", 1)[-1])


def unique_name(slug: str, taken: set[str]) -> str:
    name = slug
    n = 2
    while name in taken:
        suffix = f"-{n}"
        name = slug[: MAX_AGENT_NAME - len(suffix)] + suffix
        n += 1
    return name


def default_branch_from_symref(output: str) -> str | None:
    match = re.search(r"^ref: refs/heads/(\S+)\s+HEAD$", output, re.MULTILINE)
    return match.group(1) if match else None


def full_briefing(brief: str, path: str, branch: str) -> str:
    return (
        f"{brief.strip()}\n\n"
        f"You are in worktree {path} on branch {branch}, "
        "and the user will talk to you directly in this pane.\n"
        "Start now: explore, then implement, then verify, "
        "and stop to ask the user when a decision is genuinely theirs."
    )


def resolve_base(repo: str, explicit: str | None) -> str:
    remotes = must("git", "-C", repo, "remote").split("\n")
    tracked = [r for r in ("upstream", "origin") if r in remotes]
    for remote in tracked:
        must("git", "-C", repo, "fetch", "--quiet", remote)
    if explicit:
        must("git", "-C", repo, "rev-parse", "--verify", "--quiet", f"{explicit}^{{commit}}")
        return explicit
    if tracked:
        head = must("git", "-C", repo, "ls-remote", "--symref", tracked[0], "HEAD")
        branch = default_branch_from_symref(head)
        if not branch:
            raise RuntimeError(f"cannot find the default branch of {tracked[0]}")
        return f"{tracked[0]}/{branch}"
    for local in ("main", "master"):
        if run("git", "-C", repo, "show-ref", "--verify", "--quiet", f"refs/heads/{local}").ok:
            return local
    raise RuntimeError("no remote and no main or master branch: pass --base")


def assert_branch_is_new(repo: str, branch: str) -> None:
    must("git", "check-ref-format", "--branch", branch)
    if run("git", "-C", repo, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}").ok:
        raise RuntimeError(f"branch {branch} already exists locally")
    for remote in filter(None, must("git", "-C", repo, "remote").split("\n")):
        if must("git", "-C", repo, "ls-remote", "--heads", remote, branch):
            raise RuntimeError(f"branch {branch} already exists on {remote}")


def copy_env_files(repo: str, worktree: str) -> list[str]:
    # --directory collapses ignored directories, so nothing inside node_modules
    # or a virtualenv is mistaken for project configuration.
    listed = must(
        "git",
        "-C",
        repo,
        "ls-files",
        "-z",
        "--others",
        "--ignored",
        "--exclude-standard",
        "--directory",
    )
    files = [f for f in listed.split("\0") if f and is_env_file(f)]
    for file in files:
        target = Path(worktree, file)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(Path(repo, file), target)
    return files


def start_agent(
    report: dict[str, Any], label: str, kind: str, brief: str, path: str, branch: str
) -> bool:
    pane = str(report["pane"])

    def stuck(error: str, briefing: str) -> bool:
        tail = run("herdr", "pane", "read", pane, "--source", "visible", "--lines", "40")
        emit(
            {
                "status": "blocked",
                **report,
                "briefing": briefing,
                "error": error,
                "pane_tail": tail.stdout,
            }
        )
        return False

    live = cast("list[dict[str, Any]]", must_json("herdr", "agent", "list")["result"]["agents"])
    taken = {str(a["name"]) for a in live if a.get("name")}
    agent = unique_name(agent_slug(label), taken)
    report["agent"] = agent

    started = run("herdr", "agent", "start", agent, "--kind", kind, "--pane", pane)
    if not started.ok:
        if "agent_not_ready" not in started.message:
            raise RuntimeError(started.message)
        return stuck(started.message, "not_sent")

    prompted = run(
        "herdr",
        "agent",
        "prompt",
        agent,
        full_briefing(brief, path, branch),
        "--wait",
        "--until",
        "working",
        "--timeout",
        "60000",
    )
    if not prompted.ok:
        sent = "not_sent" if "agent_blocked" in prompted.message else "unknown"
        return stuck(prompted.message, sent)
    status = json.loads(prompted.stdout)["result"]["agent"]["agent_status"]
    if status != "working":
        return stuck(f"agent is {status}", "sent")
    emit({"status": "started", **report})
    return True


def main() -> bool:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--base")
    parser.add_argument("--label")
    parser.add_argument("--kind", default="claude")
    args = parser.parse_args()
    branch = cast(str, args.branch)
    base_arg = cast("str | None", args.base)
    label_arg = cast("str | None", args.label)

    if os.environ.get("HERDR_ENV") != "1":
        raise RuntimeError("not running inside herdr")
    if sys.stdin.isatty():
        raise RuntimeError("pass the briefing on stdin")
    brief = sys.stdin.read()
    if not brief.strip():
        raise RuntimeError("the briefing on stdin is empty")

    common_dir = must(
        "git", "-C", cast(str, args.repo), "rev-parse", "--path-format=absolute", "--git-common-dir"
    )
    repo = str(Path(common_dir).parent)
    assert_branch_is_new(repo, branch)
    base = resolve_base(repo, base_arg)
    label = label_arg or slug_from_branch(branch)

    created = must_json(
        "herdr",
        "worktree",
        "create",
        "--cwd",
        repo,
        "--branch",
        branch,
        "--base",
        base,
        "--label",
        label,
        "--no-focus",
    )["result"]
    path = str(created["worktree"]["path"])
    report: dict[str, Any] = {
        "workspace": created["workspace"]["workspace_id"],
        "label": label,
        "pane": created["root_pane"]["pane_id"],
        "branch": branch,
        "base": base,
        "path": path,
    }

    try:
        report["env_files"] = copy_env_files(repo, path)
        return start_agent(report, label, cast(str, args.kind), brief, path, branch)
    except Exception as e:  # noqa: BLE001
        # The worktree exists at this point; report it so nobody creates it again.
        emit({"status": "error", "error": f"{type(e).__name__}: {e}", **report})
        return False


if __name__ == "__main__":
    try:
        sys.exit(0 if main() else 1)
    except Exception as e:  # noqa: BLE001
        emit({"status": "error", "error": f"{type(e).__name__}: {e}"})
        sys.exit(1)
