---
name: wt-cleanup
description: Clean up a finished git worktree whose PR is merged or closed - update its linked Jira ticket, remove the worktree, close its herdr workspace, and delete the local branch, refusing when anything would be lost. Use when the user says they are done with a worktree (wt), or asks to clean up, remove, or close one.
---

# Worktree Cleanup

Tear down one worktree after its PR is merged or closed, without losing anything that was never pushed.

Requires running inside herdr: `test "${HERDR_ENV:-}" = 1`.
If the check fails, say so and stop.
Read IDs from the JSON each command returns; never predict them.

## 1. Find the target

```bash
herdr worktree list --cwd <repo>
```

Match the user's words (branch, label, PR number) against the linked worktrees (`is_linked_worktree: true`).
Never target the primary checkout.
If nothing was named or the match is ambiguous, show the linked worktrees with their PR state (step 2) and ask which.

Note whether the target's `open_workspace_id` is the workspace of your own pane (`herdr pane get "$HERDR_PANE_ID"`).
If it is, you are running inside the worktree; step 5 handles that.

## 2. Check the PR

```bash
gh pr list --head <branch> --state all --json number,state,url,headRefOid
```

- `MERGED` or `CLOSED`: continue.
- `OPEN`: stop and say so.
- No PR: stop and ask; the work may never have been pushed.

## 3. Check nothing would be lost

All of these must hold; if any fails, stop, show what would be lost, and let the user decide:

- No uncommitted or untracked changes: `git -C <path> status --porcelain` is empty.
- The local branch tip is the PR head: `git -C <path> rev-parse HEAD` equals `headRefOid`.
  A differing tip means local commits were never pushed to the PR.
- No stashes made on this branch: `git -C <repo> stash list` has no entry naming `<branch>`.

An empty `status --porcelain` also proves every submodule is clean and at its pinned commit.
Ignored files such as copied `.env` files and build output are expected to be lost.

## 4. Update the Jira ticket

Look for Jira issue keys (`[A-Z][A-Z0-9]+-[0-9]+`) in the branch name, PR title, and PR body (`gh pr view <number> --json title,body`).
If there are none, skip this step.

For each key, fetch the issue with the available Jira tools to confirm it exists, then:

- Add a comment with the PR link and its final state (merged or closed), plus a one-line summary of what the PR did.
- If the PR was merged and the issue is not already in a done status, transition it to the done status from the issue's available transitions.
- If the PR was closed without merging, or the issue clearly has other work still open (other open PRs, unchecked subtasks), comment only and ask the user whether to transition it.
- If no transition clearly means done, ask the user which one to use.

If the Jira tools are unavailable or an update fails, stop before removing anything and tell the user.

## 5. Remove

`herdr worktree remove` deletes the worktree directory and closes its workspace, including any agent running in it.
Git cannot delete a branch still checked out in a worktree, so the order matters.
Git also refuses to remove a worktree with initialized submodules, however clean.
If `git -C <path> submodule status --recursive` lists any line not starting with `-`, add `--force` to the remove command; step 3 already proved there is nothing to lose.

From another workspace, run:

```bash
herdr worktree remove --workspace <open_workspace_id>
git -C <repo> branch -D <branch>
git -C <repo> fetch --prune origin
```

If the worktree has no open workspace, use `git -C <repo> worktree remove <path>` instead of `herdr worktree remove`.

From inside the worktree, the removal kills you, so it must be the last command.
Detach HEAD to free the branch, delete it, and post the step 6 report as a herdr notification, because the pane is about to disappear:

```bash
git -C <path> checkout --detach
git -C <path> branch -D <branch>
git -C <path> fetch --prune origin
herdr notification show "<branch>: removing worktree" --body "<report>"
herdr worktree remove --workspace <open_workspace_id>
```

The herdr server finishes the removal after your process is gone; do not chain anything after it.
If the remove returns an error, you are still alive: tell the user the notification was premature and why the removal failed.

`-D` is needed because squash and rebase merges leave the branch looking unmerged; step 3 already proved the commits are on the remote.
Beyond the submodule case, never pass `--force` to either remove command unless the user explicitly asked after seeing what is dirty.
Never delete the remote branch; leave that to GitHub or the user.

## 6. Report

One or two lines: which worktree, workspace, and branch were removed, the PR link with its final state, and any Jira issue updated with its new status.
If the remote branch still exists (`git -C <repo> ls-remote --heads origin <branch>`), mention it.
