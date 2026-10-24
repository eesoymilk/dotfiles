---
name: wt-open
description: Open a git worktree as its own herdr workspace, start a coding agent in it, brief that agent on the task so it starts coding, and hand control back to the user. Use when the user asks to open, spin up, or start a worktree (wt) for a task in herdr.
---

# Worktree Open

Spin up one isolated worktree for one task, hand it to a fresh agent, and get out of the way.
The user drives the new agent from here on; you do not coordinate it.

Requires running inside herdr: `test "${HERDR_ENV:-}" = 1`.
If the check fails, say so and stop.
The installed binary is the authority on CLI syntax: run `herdr worktree` or `herdr agent` without a subcommand to print usage, or `herdr --skill` for the full guide.
Read IDs from the JSON each command returns; never predict them.

## 1. Pin down the task

You need three things: the repo, the task, and a branch name.

- Repo: the git repo of the current directory, unless the user named another one.
- Task: what the new agent should build or fix, plus any context already in this conversation that it will need.
- Branch: derive `<type>/<short-kebab-slug>` from the task, using the repo's conventional-commit types (`feat`, `fix`, `chore`, `docs`, `refactor`).
  Use the user's name if they gave one.
  Check it does not exist yet: `git -C <repo> branch --list <branch>` and `git -C <repo> ls-remote --heads origin <branch>`.

Ask only if the task itself is unclear.
Do not ask to confirm the branch name; state it in the final report.

## 2. Create the worktree

Base it on the up-to-date default branch, not on whatever is checked out locally:

```bash
git -C <repo> fetch origin
base=$(git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD)   # e.g. origin/main
herdr worktree create --cwd <repo> --branch <branch> --base "$base" --label <slug> --no-focus
```

From the result, keep `result.workspace.workspace_id`, `result.root_pane.pane_id`, and `result.worktree.path`.

If the repo has no `origin`, base on the local default branch and say so.
If herdr refuses with a repository trust error, show it to the user; never add `--trust-repository` on your own.

## 3. Copy env files

Git does not carry ignored files into a worktree.
Find them in the source checkout:

```bash
git -C <repo> ls-files --others --ignored --exclude-standard \
  | grep -Ei '(^|/)\.env($|\.)|(^|/)\.dev\.vars$|\.local\.(toml|json|ya?ml)$|(^|/)\.envrc$'
```

Copy each match into the worktree at the same relative path, creating parent directories.
Never copy tracked files such as `.env.example`.
Leave installs and builds to the new agent.

## 4. Start and brief the agent

Start it in the worktree's root pane.
Use `claude` unless the user asked for another kind:

```bash
herdr agent start <slug> --kind claude --pane <root-pane-id>
```

The agent name must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents (`herdr agent list`); the slug usually works.
Never pass permission, approval, or sandbox flags, and never change them after launch.

Write the briefing so an agent with zero access to this conversation can start immediately:

- The goal, in one or two sentences.
- The context and decisions already settled with the user, stated as decisions.
- Pointers to relevant files, issues, PRs, or docs, by path or URL.
- Anything explicitly out of scope.
- How to verify the work: the test, lint, or run command, if known.
- That it is in worktree `<path>` on branch `<branch>`, and the user will talk to it directly in this pane.
- That it should start now: explore, then implement, then verify, and stop to ask the user when a decision is genuinely theirs.

Do not restate rules the agent already loads from `AGENTS.md`.

```bash
herdr agent prompt <slug> "<briefing>" --wait --until working --timeout 60000
```

If it returns `agent_blocked` or `blocked`, read the pane (`herdr agent read <slug> --lines 40`) and tell the user what it is waiting on; do not answer dialogs for them.

## 5. Hand back

Report in a few lines, then end your turn:

- Workspace label and agent name.
- Branch and worktree path.
- Env files copied, or "none".
- A one-line summary of the briefing.

Do not wait on, read, or steer the new agent afterward unless the user asks.
