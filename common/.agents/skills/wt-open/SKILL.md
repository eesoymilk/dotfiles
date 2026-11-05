---
name: wt-open
description: Open a git worktree as its own herdr workspace, start a coding agent in it, brief that agent on the task so it starts coding, and hand control back to the user. Use when the user asks to open, spin up, or start a worktree (wt) for a task in herdr.
---

# Worktree Open

Spin up one isolated worktree for one task, hand it to a fresh agent, and get out of the way.
The user drives the new agent from here on; you do not coordinate it.

## 1. Run the script

Make one Bash call per worktree, with a 5-minute timeout.
Do not run preflight checks first; the script does them and creates nothing if they fail.

```bash
~/.agents/skills/wt-open/scripts/wt_open.py --branch <type>/<short-kebab-slug> <<'BRIEF'
<briefing>
BRIEF
```

The branch type is a conventional-commit type (`feat`, `fix`, `chore`, `docs`, `refactor`).
Use the user's branch name if they gave one, and do not ask them to confirm yours.
Ask only if the task itself is unclear.

Add these flags only when needed:

- `--repo <path>`: a repo other than the current directory's.
- `--base <ref>`: anything other than the default branch of `upstream`, or of `origin` if there is no `upstream`.
- `--label <slug>`: a workspace and agent name other than the one derived from the branch.
- `--kind <agent>`: an agent other than `claude`.

The briefing must let an agent with no access to this conversation start immediately:

- The goal, in one or two sentences.
- The context and decisions already settled with the user, stated as decisions.
- Pointers to relevant files, issues, PRs, or docs, by path or URL.
- Anything explicitly out of scope.
- How to verify the work: the test, lint, or run command, if known.

Do not restate rules the agent already loads from `AGENTS.md`.
The script appends the worktree path, the branch, and the instruction to start now.

## 2. Act on the `status` it prints

- `started`: go to step 3.
- `blocked`: the worktree exists and the agent is waiting on the dialog in `pane_tail`.
  Show the user that dialog and do not answer it for them.
  If `briefing` is `not_sent`, send it with `herdr agent prompt <agent> "<briefing>" --wait --until working --timeout 60000` once the user has cleared the dialog, adding the worktree path and branch.
  If `briefing` is `unknown`, read the pane before sending anything, because the prompt may have arrived.
- `error`: show `error` to the user.
  If the output includes `path`, the worktree already exists, so do not run the script again for this branch.
  If herdr refuses with a repository trust error, never add `--trust-repository` on your own.
  If the branch name is taken, pick another and run the script again.

## 3. Hand back

Report in a few lines, then end your turn:

- Workspace label and agent name.
- Branch, base, and worktree path.
- Env files copied, or "none".
- A one-line summary of the briefing.

Do not wait on, read, or steer the new agent afterward unless the user asks.
