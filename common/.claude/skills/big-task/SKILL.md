---
name: big-task
description: "Orchestrate a large multi-component task with multiple Claude Code agents in Herdr. Use when a task spans many components at once or a single agent is not sufficient. Covers spec grilling, work distribution, worktree decisions, Herdr pane/tab layout, monitoring, and teardown."
---

# Big Task

You are the master agent for a task too large for one agent.
Follow this procedure in order.
Requires running inside Herdr (`test "${HERDR_ENV:-}" = 1`); if not inside Herdr, tell the user and stop.

## 1. Grill the user

Interrogate the user until the spec has no open questions, down to the tiniest details.
Use AskUserQuestion in rounds; each answer usually spawns follow-ups, so keep going until a new round would produce nothing new.
Cover at minimum: exact scope and non-goals, acceptance criteria, interfaces between components, naming, error handling, testing expectations, and what existing code must not change.
Do not fill gaps with assumptions; a wrong assumption multiplied across N subagents is N times the rework.

## 2. Write the spec to a shared place

Write the agreed spec to `docs/specs/<task-slug>.md` in the repo (create the directory if needed).
Every subagent reads this file, so it must be self-contained: a subagent sees none of the conversation that produced it.
Include per-component sections that can be assigned wholesale to one agent.
Do not commit it unless the user asks.

## 3. Plan the distribution

Decide how many subagents the task needs and split the work evenly.
Even means comparable wall-clock effort, not comparable file counts.
Partition by component boundaries so no two agents edit the same files.
If two work items must touch the same file, they belong to the same agent.
Write the assignment table (agent name, scope, files owned) into the spec file.

## 4. Decide on worktrees

Use `herdr worktree` git worktrees only when agents would otherwise conflict: same files, or the task requires isolated builds or branches.
When the partition already gives each agent disjoint files, working on the same branch in the same checkout is more convenient; prefer it.
State the decision and the reason in the spec.

## 5. Spawn subagents in Herdr

Follow the herdr skill (`herdr --skill` if not in context) for exact CLI usage.
Layout heuristic, chosen for DX:

- Up to 3 subagents: split panes in the master's own tab so the user sees all progress at once (master + 3 is a comfortable maximum per tab).
- More than 3: group them into additional tabs of 3 to 4 panes each, named by component group; keep the master in the first tab.

Spawn each agent with `herdr pane split` then `herdr agent start`, give it a meaningful `[a-z0-9_-]` name, and prompt it with: the path to the spec file, its assigned section, and the instruction to report completion status back in its pane.
Never pass `--permission-mode` and never toggle permission modes after launch; the global default is auto mode, leave it.

## 6. Monitor and report

Poll with `herdr agent wait --state idle,blocked,done` and `herdr agent read`.
Unblock `blocked` agents yourself when the question is answered by the spec; escalate to the user only when it is not.
Relay meaningful progress and problems to the user as they happen, not as a data dump at the end.

## 7. Finish

Verify each component against the acceptance criteria in the spec (run the tests, do not trust agent self-reports).
Write the final outcome summary at the bottom of the spec file.
Report to the user: what was built, what was verified and how, and anything left open.

## 8. Teardown

Kill a subagent's pane only after its results are merged and its report is captured in the spec summary, so no information is lost.
Kill them one at a time, confirming each agent's work landed before closing it.
Leave nothing running when the task is done.
