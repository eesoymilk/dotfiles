from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from wt_cleanup import choose_pr, github_slug, jira_keys, loss_blockers, match_worktrees


def pr(number: int, state: str, login: str) -> dict[str, Any]:
    return {"number": number, "state": state, "headRepositoryOwner": {"login": login}}


def worktree(branch: str, path: str) -> dict[str, Any]:
    return {"branch": branch, "path": path}


def test_github_slug_reads_ssh_and_https_remotes() -> None:
    assert github_slug("git@github.com:me/repo.git") == "me/repo"
    assert github_slug("https://github.com/org/repo.dots") == "org/repo.dots"
    assert github_slug("https://github.com/org/repo/") == "org/repo"
    assert github_slug("git@gitlab.com:me/repo.git") is None


def test_jira_keys_finds_unique_keys_across_texts() -> None:
    assert jira_keys("fix/ABC-12-thing", "ABC-12 and XY2-3", "lower-case abc-1") == [
        "ABC-12",
        "XY2-3",
    ]


def test_choose_pr_ignores_other_peoples_prs_from_the_same_branch_name() -> None:
    prs = [pr(3, "MERGED", "stranger"), pr(2, "MERGED", "Me"), pr(1, "CLOSED", "me")]
    assert (choose_pr(prs, "me") or {}).get("number") == 2
    assert choose_pr(prs, "nobody") is None
    assert (choose_pr(prs, None) or {}).get("number") == 3


def test_choose_pr_prefers_an_open_pr_over_newer_history() -> None:
    prs = [pr(2, "MERGED", "me"), pr(1, "OPEN", "me")]
    assert (choose_pr(prs, "me") or {}).get("number") == 1


def test_choose_pr_skips_a_deleted_head_repository_when_filtering() -> None:
    orphan = {"number": 1, "state": "MERGED", "headRepositoryOwner": None}
    assert choose_pr([orphan], "me") is None


def test_loss_blockers_passes_only_a_finished_pr_with_nothing_local() -> None:
    merged = pr(1, "MERGED", "me")
    assert loss_blockers(merged, "", "", "") == []
    assert loss_blockers(pr(1, "CLOSED", "me"), "", "", "") == []
    assert "still open" in loss_blockers(pr(1, "OPEN", "me"), "", "", "")[0]
    assert "no PR" in loss_blockers(None, "", "", "")[0]
    assert "uncommitted" in loss_blockers(merged, "?? a", "", "")[0]
    assert "not in the PR" in loss_blockers(merged, "", "abc x", "")[0]
    assert "stashes" in loss_blockers(merged, "", "", "stash@{0}")[0]


def test_match_worktrees_prefers_an_exact_match_over_substrings() -> None:
    both = [worktree("fix/a", "/w/fix-a"), worktree("fix/a-b", "/w/fix-a-b")]
    assert len(match_worktrees(both, "fix/a")) == 1
    assert len(match_worktrees(both, "fix-a-b")) == 1
    assert len(match_worktrees(both, "a-b")) == 1
    assert len(match_worktrees(both, "fix")) == 2
    assert match_worktrees(both, "zzz") == []


FAKE_HERDR = """#!{python}
import json, os, subprocess, sys

state_dir = os.environ["FAKE_DIR"]
state_path = os.path.join(state_dir, "state.json")
with open(state_path) as f:
    state = json.load(f)
args = sys.argv[1:]


def git(*cmd):
    return subprocess.run(["git", "-C", state["repo"], *cmd], capture_output=True, text=True)


def log(entry):
    with open(os.path.join(state_dir, "herdr.log"), "a") as f:
        f.write(json.dumps(entry) + "\\n")


if args[:2] == ["worktree", "list"]:
    if state.get("garbage_list"):
        print('{{"result": {{}}}}')
        sys.exit(0)
    worktrees = []
    entries = git("worktree", "list", "--porcelain").stdout.strip().split("\\n\\n")
    for index, entry in enumerate(entries):
        fields = dict(line.split(" ", 1) for line in entry.split("\\n") if " " in line)
        path = fields["worktree"]
        worktrees.append(
            {{
                "path": path,
                "branch": fields.get("branch", "").replace("refs/heads/", "") or None,
                "is_linked_worktree": index > 0,
                "is_prunable": False,
                "open_workspace_id": state["workspaces"].get(path),
            }}
        )
    print(json.dumps({{"result": {{"worktrees": worktrees}}}}))
elif args[:2] == ["pane", "get"]:
    print(json.dumps({{"result": {{"pane": {{"workspace_id": state["own_workspace"]}}}}}}))
elif args[:2] == ["notification", "show"]:
    log({{"call": "notification", "args": args[2:]}})
    print("{{}}")
elif args[:2] == ["worktree", "remove"]:
    workspace = args[args.index("--workspace") + 1]
    force = "--force" in args
    path = next(p for p, w in state["workspaces"].items() if w == workspace)
    log(
        {{
            "call": "remove",
            "force": force,
            "branch_existed": git("branch", "--list", state["branch"]).stdout != "",
        }}
    )
    git("worktree", "remove", *(["--force"] if force else []), path)
    print("{{}}")
else:
    sys.exit(f"unexpected herdr call: {{args}}")
"""

FAKE_GH = """#!{python}
import json, os, sys

state_dir = os.environ["FAKE_DIR"]
with open(os.path.join(state_dir, "state.json")) as f:
    state = json.load(f)
if state.get("gh_fails"):
    sys.exit("gh: auth required")
slug = sys.argv[sys.argv.index("--repo") + 1]
print(json.dumps(state["prs"].get(slug, [])))
"""

SCRIPT = Path(__file__).with_name("wt_cleanup.py")
BRANCH = "fix/a"


class Sandbox:
    """A real repo and linked worktree, with fake gh and herdr on PATH."""

    def __init__(self, tmp_path: Path) -> None:
        self.root = tmp_path.resolve()
        self.origin = self.root / "github.com/me/e2e.git"
        self.repo = self.root / "repo"
        self.worktree = self.root / "wt/fix-a"
        self.bin = self.root / "bin"
        self.state_dir = self.root / "state"
        self.bin.mkdir()
        self.state_dir.mkdir()
        self.env = {
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(self.root),
            "HERDR_ENV": "1",
            "HERDR_PANE_ID": "own:p1",
            "FAKE_DIR": str(self.state_dir),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        for name, body in (("herdr", FAKE_HERDR), ("gh", FAKE_GH)):
            fake = self.bin / name
            fake.write_text(body.format(python=sys.executable))
            fake.chmod(0o755)

        self.git_at(self.root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.git_at(self.root, "init", "-q", "-b", "main", str(self.repo))
        self.git("remote", "add", "origin", str(self.origin))
        self.git("commit", "-q", "--allow-empty", "-m", "init")
        self.git("push", "-q", "origin", "main")
        self.git("worktree", "add", "-q", "-b", BRANCH, str(self.worktree))
        self.wt_git("commit", "-q", "--allow-empty", "-m", "work")
        self.wt_git("push", "-q", "origin", BRANCH)

        self.state: dict[str, Any] = {
            "repo": str(self.repo),
            "branch": BRANCH,
            "own_workspace": "other",
            "workspaces": {str(self.worktree): "w1"},
            "prs": {"me/e2e": [self.pr()]},
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

    def wt_git(self, *args: str) -> str:
        return self.git_at(self.worktree, *args)

    def pr(
        self, state: str = "MERGED", login: str = "me", title: str = "a change"
    ) -> dict[str, Any]:
        return {
            "number": 7,
            "state": state,
            "url": "https://github.com/me/e2e/pull/7",
            "title": title,
            "body": "",
            "headRefOid": self.wt_git("rev-parse", "HEAD"),
            "headRepositoryOwner": {"login": login},
        }

    def run(self, *args: str, env: dict[str, str] | None = None) -> tuple[int, dict[str, Any]]:
        (self.state_dir / "state.json").write_text(json.dumps(self.state))
        out = subprocess.run(
            [sys.executable, "-B", str(SCRIPT), "--repo", str(self.repo), *args],
            env={**self.env, **(env or {})},
            cwd=self.root,
            check=False,
            capture_output=True,
            text=True,
        )
        return out.returncode, json.loads(out.stdout)

    def herdr_log(self) -> list[dict[str, Any]]:
        log = self.state_dir / "herdr.log"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def branch_exists(self) -> bool:
        return self.git("branch", "--list", BRANCH) != ""

    def assert_intact(self) -> None:
        assert self.worktree.exists()
        assert self.branch_exists()
        assert self.herdr_log() == []

    def assert_removed(self) -> None:
        assert not self.worktree.exists()
        assert not self.branch_exists()


def test_merged_pr_removes_the_worktree_then_the_branch(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (0, "removed")
    box.assert_removed()
    assert box.herdr_log() == [{"call": "remove", "force": False, "branch_existed": True}]


def test_removal_keeps_the_remote_branch_and_reports_it(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    _, out = box.run("fix/a")
    assert out["remote_branch_exists"] is True
    assert box.git("ls-remote", "--heads", "origin", BRANCH) != ""


def test_closed_pr_removes(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prs"] = {"me/e2e": [box.pr("CLOSED")]}
    assert box.run("fix/a")[1]["status"] == "removed"
    box.assert_removed()


def test_open_pr_blocks(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prs"] = {"me/e2e": [box.pr("OPEN")]}
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "blocked")
    assert "still open" in out["blockers"][0]
    box.assert_intact()


def test_missing_pr_blocks(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prs"] = {}
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "blocked")
    assert "no PR" in out["blockers"][0]
    box.assert_intact()


def test_untracked_file_blocks(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    (box.worktree / "new.txt").write_text("x")
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "blocked")
    assert "new.txt" in out["blockers"][0]
    box.assert_intact()
    assert (box.worktree / "new.txt").exists()


def test_local_commit_missing_from_the_pr_blocks(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.wt_git("commit", "-q", "--allow-empty", "-m", "never pushed")
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "blocked")
    assert "never pushed" in out["blockers"][0]
    box.assert_intact()


def test_stash_on_the_branch_blocks(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    (box.worktree / "tracked.txt").write_text("x")
    box.wt_git("add", "tracked.txt")
    box.wt_git("stash", "-q")
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "blocked")
    assert "stash" in out["blockers"][0]
    box.assert_intact()


def test_tip_behind_the_pr_head_is_not_a_loss(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.wt_git("commit", "-q", "--allow-empty", "-m", "maintainer merge")
    box.state["prs"] = {"me/e2e": [box.pr()]}
    box.wt_git("reset", "-q", "--hard", "HEAD~1")
    assert box.run("fix/a")[1]["status"] == "removed"
    box.assert_removed()


def test_pr_head_missing_locally_is_fetched_from_the_pull_ref(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    clone = box.root / "maintainer"
    box.git_at(box.root, "clone", "-q", "-b", BRANCH, str(box.origin), str(clone))
    box.git_at(clone, "commit", "-q", "--allow-empty", "-m", "maintainer merge")
    box.git_at(clone, "push", "-q", "origin", "HEAD:refs/pull/7/head")
    pr = box.pr()
    pr["headRefOid"] = box.git_at(clone, "rev-parse", "HEAD")
    box.state["prs"] = {"me/e2e": [pr]}
    assert box.run("fix/a")[1]["status"] == "removed"
    box.assert_removed()


def test_force_overrides_blockers(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    (box.worktree / "new.txt").write_text("x")
    assert box.run("fix/a", "--force")[1]["status"] == "removed"
    box.assert_removed()
    assert box.herdr_log()[0]["force"] is True


def test_jira_keys_stop_removal_until_jira_is_done(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["prs"] = {"me/e2e": [box.pr(title="ABC-123 a change")]}
    code, out = box.run("fix/a")
    assert (code, out["status"], out["jira_keys"]) == (0, "needs_jira", ["ABC-123"])
    box.assert_intact()
    assert box.run("fix/a", "--jira-done")[1]["status"] == "removed"
    box.assert_removed()


def test_blockers_take_priority_over_jira_done(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    (box.worktree / "new.txt").write_text("x")
    assert box.run("fix/a", "--jira-done")[1]["status"] == "blocked"
    box.assert_intact()


def test_no_target_outside_a_worktree_only_lists(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run()
    assert (code, out["status"]) == (0, "choose")
    assert [w["branch"] for w in out["worktrees"]] == [BRANCH]
    box.assert_intact()


def test_unmatched_target_only_lists(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    assert box.run("zzz")[1]["status"] == "choose"
    box.assert_intact()


def test_primary_checkout_is_never_a_target(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    assert box.run("main", "--force")[1]["status"] == "choose"
    assert box.repo.exists()
    box.assert_intact()


def test_ambiguous_target_only_lists(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.git("worktree", "add", "-q", "-b", "fix/b", str(box.root / "wt/fix-b"))
    assert box.run("fix")[1]["status"] == "choose"
    box.assert_intact()


def test_target_can_be_a_pr_number(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    assert box.run("#7")[1]["status"] == "removed"
    box.assert_removed()


def test_removal_from_inside_deletes_the_branch_and_notifies_first(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["own_workspace"] = "w1"
    assert box.run()[1]["status"] == "removed"
    box.assert_removed()
    notification, removal = box.herdr_log()
    assert notification["call"] == "notification"
    assert "PR #7 merged" in notification["args"][-1]
    assert removal == {"call": "remove", "force": False, "branch_existed": False}


def test_worktree_without_a_workspace_is_removed_through_git(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["workspaces"] = {}
    assert box.run("fix/a")[1]["status"] == "removed"
    box.assert_removed()
    assert box.herdr_log() == []


def test_initialized_submodule_adds_force_to_a_clean_removal(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    sub = box.root / "sub"
    box.git_at(box.root, "init", "-q", "-b", "main", str(sub))
    box.git_at(sub, "commit", "-q", "--allow-empty", "-m", "sub")
    box.wt_git("-c", "protocol.file.allow=always", "submodule", "add", "-q", str(sub), "vendor")
    box.wt_git("commit", "-q", "-m", "add submodule")
    box.state["prs"] = {"me/e2e": [box.pr()]}
    assert box.run("fix/a")[1]["status"] == "removed"
    box.assert_removed()
    assert box.herdr_log()[0]["force"] is True


def test_fork_uses_the_upstream_pr_and_ignores_strangers(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.git("remote", "add", "upstream", str(box.root / "github.com/org/e2e.git"))
    box.state["prs"] = {"org/e2e": [box.pr(login="stranger"), box.pr(login="me")]}
    box.state["prs"]["org/e2e"][0]["number"] = 99
    code, out = box.run("fix/a", "--jira-done")
    assert (code, out["status"], out["pr"]["number"]) == (0, "removed", 7)


def test_fork_with_only_a_strangers_pr_blocks(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.git("remote", "add", "upstream", str(box.root / "github.com/org/e2e.git"))
    box.state["prs"] = {"org/e2e": [box.pr(login="stranger")]}
    assert box.run("fix/a")[1]["status"] == "blocked"
    box.assert_intact()


def test_gh_failure_removes_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["gh_fails"] = True
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "error")
    assert "auth required" in out["error"]
    box.assert_intact()


def test_unexpected_herdr_output_removes_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    box.state["garbage_list"] = True
    code, out = box.run("fix/a")
    assert (code, out["status"]) == (1, "error")
    box.assert_intact()


def test_outside_herdr_removes_nothing(tmp_path: Path) -> None:
    box = Sandbox(tmp_path)
    code, out = box.run("fix/a", env={"HERDR_ENV": "0"})
    assert (code, out["status"]) == (1, "error")
    box.assert_intact()
