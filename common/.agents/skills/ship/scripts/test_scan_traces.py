from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from scan_traces import added_lines, is_exempt, rules_matching

SCRIPT = Path(__file__).with_name("scan_traces.py")
EM_DASH = chr(0x2014)


class Repo:
    def __init__(self, tmp_path: Path) -> None:
        self.root = tmp_path.resolve() / "repo"
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(tmp_path),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        origin = tmp_path.resolve() / "origin.git"
        subprocess.run(
            ["git", "init", "-q", "--bare", "-b", "main", str(origin)], env=self.env, check=True
        )
        subprocess.run(
            ["git", "init", "-q", "-b", "main", str(self.root)], env=self.env, check=True
        )
        self.git("remote", "add", "origin", str(origin))
        self.git("commit", "-q", "--allow-empty", "-m", "init")
        self.git("push", "-q", "origin", "main")
        self.git("fetch", "-q", "origin")
        self.git("switch", "-q", "-c", "feat/x")

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=self.root,
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def stage(self, path: str, text: str) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        self.git("add", path)

    def scan(self, *args: str, text: str | None = None) -> tuple[int, dict[str, Any]]:
        out = subprocess.run(
            [sys.executable, "-B", str(SCRIPT), *args],
            cwd=self.root,
            env=self.env,
            input=text if text is not None else "",
            check=False,
            capture_output=True,
            text=True,
        )
        return out.returncode, json.loads(out.stdout)


def test_rules_flag_session_traces() -> None:
    cases = {
        "Co-Authored-By: Claude Opus <noreply@anthropic.com>": "attribution",
        "Generated with Claude Code": "attribution",
        "Signed-off-by: Bot <noreply@anthropic.com>": "attribution",
        "\U0001f916 shipped": "attribution",
        "# added by Claude": "agent-authorship",
        "// written by an AI": "agent-authorship",
        "# Lead decision 2026-08-31": "decision-note",
        "# as discussed": "conversation",
        "# per user request": "conversation",
        "# as we discussed": "conversation",
        "# per our discussion": "conversation",
        "Co-Authored-By: Opus 5.5 <x@example.com>": "attribution",
        "# 2026-08-31 decision": "decision-note",
        "# Decided 2026-08-31": "decision-note",
        "# the user asked for this": "conversation",
        "# earlier in this session we chose": "conversation",
        "# per the PR review": "review-reference",
        "# review comment said so": "review-reference",
        f"a {EM_DASH} b": "em-dash",
    }
    for line, rule in cases.items():
        assert rule in rules_matching(line), line


def test_rules_leave_ordinary_code_alone() -> None:
    for line in (
        "import anthropic",
        "model = 'claude-opus-5-5'",
        "Co-Authored-By: A Person <a@example.com>",
        "user = get_user(request)",
        "decision = choose(options)",
        "a - b",
        "# Review the config before starting.",
        "conversation = load_conversation(id)",
        "limit = 5  # requests per user",
        "# position updated by cursor",
        "# as requested by caller",
        "# removed from review queue",
        "Co-Authored-By: Claudette Smith <c@example.com>",
    ):
        assert rules_matching(line) == [], line


def test_added_lines_track_paths_and_numbers() -> None:
    diff = (
        "diff --git a/a.py b/a.py\n--- /dev/null\n+++ b/a.py\n@@ -0,0 +3,2 @@\n+one\n+two\n"
        "diff --git a/b.py b/b.py\n--- a/b.py\n+++ b/b.py\n@@ -9 +20 @@\n-gone\n+three\n"
    )
    assert list(added_lines(diff)) == [
        ("a.py", 3, "one"),
        ("a.py", 4, "two"),
        ("b.py", 20, "three"),
    ]


def test_added_line_that_looks_like_a_file_header_is_still_a_line() -> None:
    diff = "diff --git a/a.py b/a.py\n--- a/a.py\n+++ b/a.py\n@@ -0,0 +1,2 @@\n+++ x\n+y\n"
    assert list(added_lines(diff)) == [("a.py", 1, "++ x"), ("a.py", 2, "y")]


def test_path_with_a_space_keeps_its_exact_name() -> None:
    diff = "diff --git a/my d/x b/my d/x\n--- a/my d/x\t\n+++ b/my d/x\t\n@@ -0,0 +1 @@\n+y\n"
    assert list(added_lines(diff)) == [("my d/x", 1, "y")]


def test_rule_files_are_exempt() -> None:
    assert is_exempt("AGENTS.md")
    assert is_exempt("x/CLAUDE.md")
    assert is_exempt("common/.agents/skills/ship/SKILL.md")
    assert not is_exempt("src/agents.py")
    assert not is_exempt("app/skills/ship/handler.py")
    assert not is_exempt("foo.agents/skills/ship/x.py")


def test_clean_branch_passes(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("a.py", "x = 1\n")
    code, out = repo.scan()
    assert (code, out["status"], out["base"]) == (0, "clean", "origin/main")


def test_staged_trace_is_reported_with_its_location(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("src/a.py", "x = 1\n# as discussed\n")
    code, out = repo.scan()
    assert (code, out["status"]) == (1, "traces")
    assert out["findings"] == [
        {"where": "src/a.py:2", "rule": "conversation", "line": "# as discussed"}
    ]


def test_rule_files_do_not_produce_findings(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("AGENTS.md", "No notes like 'as discussed'.\n")
    assert repo.scan()[0] == 0


def test_unstaged_and_untracked_changes_are_out_of_scope(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("a.py", "x = 1\n")
    (repo.root / "a.py").write_text("x = 1\n# as discussed\n")
    (repo.root / "other.py").write_text("# added by Claude\n")
    assert repo.scan()[0] == 0


def test_trace_committed_on_the_branch_is_reported(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("a.py", "# added by Claude\n")
    repo.git("commit", "-q", "-m", "feat: x")
    code, out = repo.scan()
    assert code == 1
    assert re.fullmatch(r"commit \w+ a\.py:1", out["findings"][0]["where"])


def test_trace_removed_by_a_later_commit_is_still_reported(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("a.py", "# added by Claude\n")
    repo.git("commit", "-q", "-m", "feat: x")
    repo.stage("a.py", "x = 1\n")
    repo.git("commit", "-q", "-m", "fix: y")
    assert repo.scan()[0] == 1


def test_line_starting_with_plus_signs_is_scanned(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("a.txt", "a\n++ as discussed\n")
    assert repo.scan()[1]["findings"][0]["where"] == "a.txt:2"


def test_separate_index_is_what_gets_scanned(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.stage("unrelated.py", "# as discussed\n")
    other = repo.root / ".git/ship.index"
    repo.env["GIT_INDEX_FILE"] = str(other)
    repo.git("read-tree", "HEAD")
    repo.stage("a.py", "x = 1\n")
    assert repo.scan()[0] == 0


def test_commit_message_is_scanned(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.git(
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
    )
    code, out = repo.scan()
    assert code == 1
    assert out["findings"][0]["where"].startswith("commit ")
    assert out["findings"][0]["rule"] == "attribution"


def test_commits_already_on_the_base_are_ignored(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.git("switch", "-q", "main")
    repo.git("commit", "-q", "--allow-empty", "-m", "old: as discussed")
    repo.git("push", "-q", "origin", "main")
    repo.git("fetch", "-q", "origin")
    repo.git("switch", "-q", "-c", "feat/y")
    assert repo.scan()[0] == 0


def test_draft_text_is_scanned_only_with_stdin(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    assert repo.scan(text="Generated with Claude Code")[0] == 0
    code, out = repo.scan("--stdin", text="Title\n\nGenerated with Claude Code")
    assert code == 1
    assert out["findings"][0]["where"] == "draft text"


def test_upstream_default_branch_wins(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    upstream = tmp_path.resolve() / "upstream.git"
    subprocess.run(
        ["git", "init", "-q", "--bare", "-b", "dev", str(upstream)], env=repo.env, check=True
    )
    repo.git("remote", "add", "upstream", str(upstream))
    repo.git("push", "-q", "upstream", "HEAD:dev")
    repo.git("fetch", "-q", "upstream")
    assert repo.scan()[1]["base"] == "upstream/dev"


def test_explicit_base_is_used(tmp_path: Path) -> None:
    repo = Repo(tmp_path)
    repo.git("commit", "-q", "--allow-empty", "-m", "as discussed")
    repo.git("branch", "stacked")
    assert repo.scan("--base", "stacked")[0] == 0


def test_unknown_base_is_an_error(tmp_path: Path) -> None:
    code, out = Repo(tmp_path).scan("--base", "nope")
    assert (code, out["status"]) == (1, "error")
