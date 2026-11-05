---
name: wt-cleanup
description: Clean up a finished git worktree whose PR is merged or closed - update its linked Jira ticket, remove the worktree, close its herdr workspace, and delete the local branch, refusing when anything would be lost. Use when the user says they are done with a worktree (wt), or asks to clean up, remove, or close one.
---

# Worktree Cleanup

Tear down one worktree after its PR is merged or closed, without losing anything that was never pushed.

## 1. Run the script

Do not run preflight checks first; the script does them and removes nothing if they fail.

```bash
~/.agents/skills/wt-cleanup/scripts/wt_cleanup.py [<branch, directory name, or PR number>]
```

With no target, it picks the worktree of the workspace you are running in.
Add `--repo <path>` if the worktree belongs to a repo other than the current directory's.

Removal closes the worktree's workspace, including any agent in it, and deletes the local branch.
If the target is your own workspace, removal ends this session, and the result arrives as a herdr notification instead of as output.
The remote branch is never deleted.

## 2. Act on the `status` it prints

- `removed`: go to step 3.
- `choose`: nothing was removed, because no single worktree matched.
  Show the listed worktrees with their PR state and `blockers`, and ask which one to remove.
- `blocked`: nothing was removed.
  Show the user `blockers`.
  Run again with `--force` only if the user explicitly accepts losing that work after seeing it.
- `needs_jira`: nothing was removed yet; update Jira as described below, then run again with `--jira-done`.
- `error`: show `error` to the user.
  If you targeted your own workspace, the notification may be premature, so tell the user the removal failed.

Ignored files such as copied `.env` files and build output are expected to be lost and are not blockers.

### Updating Jira

`jira_keys` lists strings shaped like Jira keys, so some may not be real issues.
Fetch each one with the available Jira tools to confirm it exists, then:

- Add a comment with the PR link and its final state, plus a one-line summary of what the PR did.
- If the PR was merged and the issue is not already done, transition it to the done status from its available transitions.
- If the PR was closed without merging, or the issue clearly has other work still open, comment only and ask the user whether to transition it.
- If no transition clearly means done, ask the user which one to use.

If the Jira tools are unavailable or an update fails, stop and tell the user; do not pass `--jira-done`.

## 3. Report

One or two lines: which worktree, workspace, and branch were removed, the PR link with its final state, and any Jira issue updated with its new status.
If `remote_branch_exists` is true, mention it.
