#!/usr/bin/env python3
"""Remove a finished git worktree, its herdr workspace, and its local branch.

Refuses when unpushed work would be lost. Prints one JSON object.
"""
# pyright: strict

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any, NamedTuple, cast

JIRA_KEY = re.compile(r"\b[A-Z][A-Z0-9]+-[0-9]+\b")
FINISHED_STATES = ("MERGED", "CLOSED")


class Result(NamedTuple):
    ok: bool
    stdout: str
    stderr: str


class Assessment(NamedTuple):
    worktree: dict[str, Any]
    branch: str | None
    pr: dict[str, Any] | None
    blockers: list[str]


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
        raise RuntimeError(f"{' '.join(cmd)}: {result.stderr or result.stdout}")
    return result.stdout


def emit(report: dict[str, Any]) -> None:
    print(json.dumps(report))


def github_slug(url: str) -> str | None:
    match = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url)
    return match.group(1) if match else None


def jira_keys(*texts: str) -> list[str]:
    return list(dict.fromkeys(key for text in texts for key in JIRA_KEY.findall(text)))


def choose_pr(prs: Sequence[dict[str, Any]], owner: str | None) -> dict[str, Any] | None:
    """Pick the PR that decides a branch's fate: an open one wins over history."""

    def is_mine(pr: dict[str, Any]) -> bool:
        head_owner = cast("dict[str, Any] | None", pr.get("headRepositoryOwner"))
        return (
            head_owner is not None and str(head_owner["login"]).lower() == cast(str, owner).lower()
        )

    mine = [pr for pr in prs if is_mine(pr)] if owner else list(prs)
    return next((pr for pr in mine if pr["state"] not in FINISHED_STATES), None) or (
        mine[0] if mine else None
    )


def loss_blockers(
    pr: dict[str, Any] | None, dirty: str, local_only: str, stashes: str
) -> list[str]:
    blockers: list[str] = []
    if pr is None:
        blockers.append("no PR found: the work may never have been pushed")
    elif pr["state"] not in FINISHED_STATES:
        blockers.append(f"PR #{pr['number']} is still {str(pr['state']).lower()}")
    if dirty:
        blockers.append(f"uncommitted or untracked changes:\n{dirty}")
    if local_only:
        blockers.append(f"commits not in the PR:\n{local_only}")
    if stashes:
        blockers.append(f"stashes on this branch:\n{stashes}")
    return blockers


def match_worktrees(worktrees: Sequence[dict[str, Any]], target: str) -> list[dict[str, Any]]:
    def names(worktree: dict[str, Any]) -> tuple[str, str]:
        return str(worktree.get("branch") or ""), Path(str(worktree["path"])).name

    exact = [w for w in worktrees if target in names(w)]
    if exact:
        return exact
    return [w for w in worktrees if any(target in name for name in names(w))]


def remote_slugs(repo: str) -> list[tuple[str, str]]:
    remotes = must("git", "-C", repo, "remote").split("\n")
    slugs: list[tuple[str, str]] = []
    for name in ("upstream", "origin"):
        if name in remotes:
            slug = github_slug(must("git", "-C", repo, "remote", "get-url", name))
            if slug:
                slugs.append((name, slug))
    return slugs


def find_pr(repo: str, branch: str) -> tuple[dict[str, Any], str] | None:
    remotes = remote_slugs(repo)
    origin_owner = next((slug.split("/")[0] for name, slug in remotes if name == "origin"), None)
    # A fork's PRs live on upstream, where other people can use the same branch
    # name, so upstream results count only when the head is on the user's fork.
    for name, slug in remotes:
        prs = cast(
            "list[dict[str, Any]]",
            json.loads(
                must(
                    "gh",
                    "pr",
                    "list",
                    "--repo",
                    slug,
                    "--head",
                    branch,
                    "--state",
                    "all",
                    "--json",
                    "number,state,url,title,body,headRefOid,headRepositoryOwner",
                )
            ),
        )
        pr = choose_pr(prs, None if name == "origin" else origin_owner)
        if pr:
            return pr, name
    return None


def local_only_commits(path: str, pr: dict[str, Any], remote: str) -> str:
    """List commits on HEAD missing from the PR head; a tip merely behind it is fine."""
    oid = str(pr["headRefOid"])
    if not run("git", "-C", path, "cat-file", "-e", f"{oid}^{{commit}}").ok:
        must("git", "-C", path, "fetch", "--quiet", remote, f"refs/pull/{pr['number']}/head")
    return must("git", "-C", path, "log", "--oneline", f"{oid}..HEAD")


def assess(repo: str, worktree: dict[str, Any]) -> Assessment:
    path = str(worktree["path"])
    branch = cast("str | None", worktree.get("branch"))
    found = find_pr(repo, branch) if branch else None
    pr = found[0] if found else None
    stashes = ""
    if branch:
        lines = must("git", "-C", repo, "stash", "list").split("\n")
        stashes = "\n".join(line for line in lines if branch in line)
    blockers = loss_blockers(
        pr,
        must("git", "-C", path, "status", "--porcelain"),
        local_only_commits(path, *found) if found else "",
        stashes,
    )
    return Assessment(worktree, branch, pr, blockers)


def summary(a: Assessment) -> dict[str, Any]:
    pr = a.pr and {k: a.pr[k] for k in ("number", "state", "url", "title")}
    return {
        "branch": a.branch,
        "path": a.worktree["path"],
        "workspace": a.worktree.get("open_workspace_id"),
        "pr": pr,
        "blockers": a.blockers,
    }


def select_target(
    repo: str, linked: Sequence[dict[str, Any]], target: str | None, own_workspace: str
) -> Assessment | list[Assessment]:
    """Return the single worktree meant, or every candidate when that is unclear."""
    if target is None:
        own = next((w for w in linked if w.get("open_workspace_id") == own_workspace), None)
        return assess(repo, own) if own else [assess(repo, w) for w in linked]
    pr_number = re.fullmatch(r"#?(\d+)", target)
    if pr_number:
        assessed = [assess(repo, w) for w in linked]
        hits = [a for a in assessed if a.pr and str(a.pr["number"]) == pr_number.group(1)]
        return hits[0] if len(hits) == 1 else assessed
    hits = match_worktrees(linked, target)
    return assess(repo, hits[0]) if len(hits) == 1 else [assess(repo, w) for w in linked]


def remove(repo: str, a: Assessment, own_workspace: str, force: bool) -> dict[str, Any]:
    path = str(a.worktree["path"])
    branch = a.branch
    if not branch:
        raise RuntimeError(f"{path} has a detached HEAD")
    workspace = cast("str | None", a.worktree.get("open_workspace_id"))
    # Git refuses to remove a worktree with initialized submodules, however clean.
    submodules = must("git", "-C", path, "submodule", "status", "--recursive").split("\n")
    has_submodules = any(line and not line.startswith("-") for line in submodules)
    force_flag = ["--force"] if force or has_submodules else []
    has_origin = "origin" in must("git", "-C", repo, "remote").split("\n")
    remote_branch_exists = (
        has_origin and must("git", "-C", repo, "ls-remote", "--heads", "origin", branch) != ""
    )
    report = {"status": "removed", **summary(a), "remote_branch_exists": remote_branch_exists}

    def prune() -> None:
        if has_origin:
            must("git", "-C", repo, "fetch", "--quiet", "--prune", "origin")

    if workspace and workspace == own_workspace:
        # Removing this workspace kills this process, so the branch goes first
        # and the report travels by notification.
        must("git", "-C", path, "checkout", "--quiet", "--detach")
        must("git", "-C", repo, "branch", "-D", branch)
        prune()
        pr = (
            f"PR #{a.pr['number']} {str(a.pr['state']).lower()}: {a.pr['url']}" if a.pr else "no PR"
        )
        remote = "; remote branch still exists" if remote_branch_exists else ""
        must("herdr", "notification", "show", f"{branch}: removing worktree", "--body", pr + remote)
        must("herdr", "worktree", "remove", "--workspace", workspace, *force_flag)
        return report

    if workspace:
        must("herdr", "worktree", "remove", "--workspace", workspace, *force_flag)
    else:
        must("git", "-C", repo, "worktree", "remove", path, *force_flag)
    must("git", "-C", repo, "branch", "-D", branch)
    prune()
    return report


def main() -> bool:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("target", nargs="?")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--jira-done", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    target = cast("str | None", args.target)
    force = cast(bool, args.force)
    jira_done = cast(bool, args.jira_done)

    if os.environ.get("HERDR_ENV") != "1":
        raise RuntimeError("not running inside herdr")
    pane_id = os.environ.get("HERDR_PANE_ID")
    if not pane_id:
        raise RuntimeError("HERDR_PANE_ID is not set")

    common_dir = must(
        "git", "-C", cast(str, args.repo), "rev-parse", "--path-format=absolute", "--git-common-dir"
    )
    repo = str(Path(common_dir).parent)
    listed = json.loads(must("herdr", "worktree", "list", "--cwd", repo))
    worktrees = cast("list[dict[str, Any]]", listed["result"]["worktrees"])
    linked = [w for w in worktrees if w["is_linked_worktree"] and not w.get("is_prunable")]
    pane = json.loads(must("herdr", "pane", "get", pane_id))
    own_workspace = str(pane["result"]["pane"]["workspace_id"])

    selected = select_target(repo, linked, target, own_workspace)
    if isinstance(selected, list):
        emit({"status": "choose", "target": target, "worktrees": [summary(a) for a in selected]})
        return True

    if selected.blockers and not force:
        emit({"status": "blocked", **summary(selected)})
        return False

    pr = selected.pr or {}
    keys = jira_keys(selected.branch or "", str(pr.get("title") or ""), str(pr.get("body") or ""))
    if keys and not jira_done:
        emit({"status": "needs_jira", **summary(selected), "jira_keys": keys})
        return True

    emit(remove(repo, selected, own_workspace, force))
    return True


if __name__ == "__main__":
    try:
        sys.exit(0 if main() else 1)
    except Exception as e:  # noqa: BLE001
        emit({"status": "error", "error": f"{type(e).__name__}: {e}"})
        sys.exit(1)
