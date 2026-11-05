from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from wt_open import (
    agent_slug,
    default_branch_from_symref,
    full_briefing,
    is_env_file,
    slug_from_branch,
    unique_name,
)


def test_is_env_file_selects_local_configuration_only() -> None:
    for path in (".env", ".env.local", "api/.env", ".dev.vars", ".envrc", "a.local.yml"):
        assert is_env_file(path), path
    for path in (".env/", ".env.d/", "environment.ts", "my.env", "node_modules/", "a.local.txt"):
        assert not is_env_file(path), path


def test_slugs_are_always_valid_agent_names() -> None:
    assert slug_from_branch("fix/cookbook-sweep-by-id") == "cookbook-sweep-by-id"
    assert slug_from_branch("no-type") == "no-type"
    assert agent_slug("123 Foo.Bar") == "foo-bar"
    assert agent_slug("123") == "wt"
    for text in ("x" * 50, "a-" * 30, "feat/Über Cool"):
        assert re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", slug_from_branch(text)), text


def test_unique_name_adds_a_suffix_within_the_length_limit() -> None:
    assert unique_name("a", set()) == "a"
    assert unique_name("a", {"a", "a-2"}) == "a-3"
    long = "x" * 32
    assert unique_name(long, {long}) == "x" * 30 + "-2"


def test_default_branch_from_symref_reads_ls_remote_output() -> None:
    assert default_branch_from_symref("ref: refs/heads/dev\tHEAD\nabc123\tHEAD") == "dev"
    assert default_branch_from_symref("abc123\tHEAD") is None


def test_full_briefing_names_the_worktree_and_says_to_start() -> None:
    text = full_briefing("  Goal: x\n", "/w/p", "fix/x")
    assert text.startswith("Goal: x\n\nYou are in worktree /w/p on branch fix/x")
    assert "Start now" in text


FAKE_HERDR = """#!{python}
import json, os, subprocess, sys

state_dir = os.environ["FAKE_DIR"]
with open(os.path.join(state_dir, "state.json")) as f:
    state = json.load(f)
args = sys.argv[1:]


def log(entry):
    with open(os.path.join(state_dir, "herdr.log"), "a") as f:
        f.write(json.dumps(entry) + "\\n")


def flag(name):
    return args[args.index(name) + 1]


if args[:2] == ["worktree", "create"]:
    path = os.path.join(state["worktrees"], flag("--label"))
    log({{"call": "create", "cwd": flag("--cwd"), "base": flag("--base"), "label": flag("--label")}})
    subprocess.run(
        ["git", "-C", flag("--cwd"), "worktree", "add", "-q", "-b", flag("--branch"), path, flag("--base")],
        check=True,
    )
    print(json.dumps({{"result": {{
        "root_pane": {{"pane_id": "w1:p1"}},
        "workspace": {{"workspace_id": "w1"}},
        "worktree": {{"path": path}},
    }}}}))
elif args[:2] == ["agent", "list"]:
    if state.get("list_fails"):
        sys.exit("agent list failed")
    print(json.dumps({{"result": {{"agents": [{{"name": n}} for n in state["agents"]] + [{{}}]}}}}))
elif args[:2] == ["agent", "start"]:
    log({{"call": "start", "name": args[2], "kind": flag("--kind")}})
    if state.get("start_error"):
        sys.exit(state["start_error"])
    print("{{}}")
elif args[:2] == ["agent", "prompt"]:
    log({{"call": "prompt", "name": args[2], "text": args[3]}})
    if state.get("prompt_error"):
        sys.exit(state["prompt_error"])
    print(json.dumps({{"result": {{"agent": {{"agent_status": state["prompt_status"]}}}}}}))
elif args[:2] == ["pane", "read"]:
    print("Do you trust this folder?")
else:
    sys.exit(f"unexpected herdr call: {{args}}")
"""

SCRIPT = Path(__file__).with_name("wt_open.py")
BRANCH = "fix/new-thing"


class Sandbox:
    """A real repo with a fake herdr on PATH."""

    def __init__(self, tmp_path: Path, remote: bool = True) -> None:
        self.root = tmp_path.resolve()
        self.repo = self.root / "repo"
        self.origin = self.root / "origin.git"
        self.bin = self.root / "bin"
        self.state_dir = self.root / "state"
        self.bin.mkdir()
        self.state_dir.mkdir()
        self.env = {
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(self.root),
            "HERDR_ENV": "1",
            "FAKE_DIR": str(self.state_dir),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        fake = self.bin / "herdr"
        fake.write_text(FAKE_HERDR.format(python=sys.executable))
        fake.chmod(0o755)

        self.git_at(self.root, "init", "-q", "-b", "main", str(self.repo))
        (self.repo / ".gitignore").write_text(".env\n.env.*\n!.env.example\nnode_modules/\n")
        (self.repo / ".env.example").write_text("TRACKED=1\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "init")
        if remote:
            self.git_at(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
            self.git("remote", "add", "origin", str(self.origin))
            self.git("push", "-q", "origin", "main")

        self.state: dict[str, Any] = {
            "worktrees": str(self.root / "wt"),
            "agents": [],
            "prompt_status": "working",
        }

    def git_at(self, cwd: Path, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(cwd), *args],
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def git(self, *args: str) -> str:
        return self.git_at(self.repo, *args)

    def run(
        self, *args: str, brief: str = "Goal: x\n", env: dict[str, str] | None = None
    ) -> tuple[int, dict[str, Any]]:
        (self.state_dir / "state.json").write_text(json.dumps(self.state))
        out = subprocess.run(
            [sys.executable, "-B", str(SCRIPT), *args],
            input=brief,
            env={**self.env, **(env or {})},
            cwd=self.repo,
            check=False,
            capture_output=True,
            text=True,
        )
        return out.returncode, json.loads(out.stdout)

    def calls(self) -> list[dict[str, Any]]:
        log = self.state_dir / "herdr.log"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def call(self, name: str) -> dict[str, Any]:
        return next(c for c in self.calls() if c["call"] == name)

    def branch_exists(self, branch: str = BRANCH) -> bool:
        return self.git("branch", "--list", branch) != ""

    def assert_nothing_created(self) -> None:
        assert self.calls() == []
        assert not (self.root / "wt").exists()


def test_opens_a_worktree_and_briefs_the_agent(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"]) == (0, "started")
    assert (out["branch"], out["base"], out["agent"]) == (BRANCH, "origin/main", "new-thing")
    assert box.branch_exists()
    assert box.call("start") == {"call": "start", "name": "new-thing", "kind": "claude"}
    text = box.call("prompt")["text"]
    assert text.startswith("Goal: x")
    assert f"worktree {out['path']} on branch {BRANCH}" in text


def test_copies_ignored_env_files_and_keeps_their_mode(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    (box.repo / ".env").write_text("SECRET=1\n")
    (box.repo / ".env").chmod(0o600)
    (box.repo / "node_modules/pkg").mkdir(parents=True)
    (box.repo / "node_modules/pkg/.env").write_text("NOT_OURS=1\n")
    (box.repo / "api").mkdir()
    (box.repo / "api/.env.local").write_text("NESTED=1\n")
    _, out = box.run("--branch", BRANCH)
    worktree = Path(out["path"])
    assert sorted(out["env_files"]) == [".env", "api/.env.local"]
    assert (worktree / ".env").read_text() == "SECRET=1\n"
    assert (worktree / ".env").stat().st_mode & 0o777 == 0o600
    assert (worktree / "api/.env.local").exists()
    assert not (worktree / "node_modules").exists()


def test_upstream_default_branch_wins_over_origin(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    upstream = box.root / "upstream.git"
    box.git_at(box.root, "init", "-q", "--bare", "-b", "dev", str(upstream))
    box.git("remote", "add", "upstream", str(upstream))
    box.git("push", "-q", "upstream", "main:dev")
    assert box.run("--branch", BRANCH)[1]["base"] == "upstream/dev"
    assert box.call("create")["base"] == "upstream/dev"


def test_explicit_base_is_used(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.git("push", "-q", "origin", "main:stacked")
    assert box.run("--branch", BRANCH, "--base", "origin/stacked")[1]["base"] == "origin/stacked"


def test_unknown_base_creates_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run("--branch", BRANCH, "--base", "origin/nope")
    assert (code, out["status"]) == (1, "error")
    box.assert_nothing_created()


def test_repo_without_a_remote_uses_the_local_default_branch(tmp_path: Path) -> None:
    box = Sandbox(tmp_path, remote=False)
    assert box.run("--branch", BRANCH)[1]["base"] == "main"


def test_existing_local_branch_creates_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.git("branch", BRANCH)
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"]) == (1, "error")
    assert "exists locally" in out["error"]
    box.assert_nothing_created()


def test_existing_remote_branch_creates_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.git("push", "-q", "origin", f"main:{BRANCH}")
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"]) == (1, "error")
    assert "exists on origin" in out["error"]
    box.assert_nothing_created()


def test_empty_briefing_creates_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run("--branch", BRANCH, brief="  \n")
    assert (code, out["status"]) == (1, "error")
    box.assert_nothing_created()


def test_outside_herdr_creates_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run("--branch", BRANCH, env={"HERDR_ENV": "0"})
    assert (code, out["status"]) == (1, "error")
    box.assert_nothing_created()


def test_running_inside_a_worktree_targets_the_primary_checkout(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    linked = box.root / "linked"
    box.git("worktree", "add", "-q", "-b", "fix/other", str(linked))
    box.run("--branch", BRANCH, "--repo", str(linked))
    assert box.call("create")["cwd"] == str(box.repo)


def test_agent_name_avoids_live_agents(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["agents"] = ["new-thing", "new-thing-2"]
    assert box.run("--branch", BRANCH)[1]["agent"] == "new-thing-3"


def test_label_and_kind_are_passed_through(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    _, out = box.run("--branch", BRANCH, "--label", "custom", "--kind", "codex")
    assert (out["label"], out["agent"]) == ("custom", "custom")
    assert box.call("start")["kind"] == "codex"


def test_startup_dialog_reports_blocked_without_sending_the_briefing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["start_error"] = '{"error":{"code":"agent_not_ready"}}'
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"], out["briefing"]) == (1, "blocked", "not_sent")
    assert "trust this folder" in out["pane_tail"]
    assert out["path"]
    assert [c["call"] for c in box.calls()] == ["create", "start"]


def test_other_start_failure_reports_an_error_with_the_worktree(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["start_error"] = "unknown agent kind"
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"]) == (1, "error")
    assert "unknown agent kind" in out["error"]
    assert out["path"]


def test_prompt_rejected_by_a_dialog_was_not_sent(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prompt_error"] = '{"error":{"code":"agent_blocked"}}'
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"], out["briefing"]) == (1, "blocked", "not_sent")


def test_prompt_timeout_may_have_been_sent(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prompt_error"] = '{"error":{"code":"timeout"}}'
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"], out["briefing"]) == (1, "blocked", "unknown")


def test_agent_not_working_after_the_prompt_is_blocked(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prompt_status"] = "blocked"
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"], out["briefing"]) == (1, "blocked", "sent")


def test_failure_after_creation_reports_the_worktree(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["list_fails"] = True
    code, out = box.run("--branch", BRANCH)
    assert (code, out["status"]) == (1, "error")
    assert Path(out["path"]).exists()
