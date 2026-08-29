---
name: big-task
description: Run a large multi-part task end to end - grill the user into a self-contained spec, split it across N parallel Claude agents in herdr, coordinate them live, and deliver a clean report. Use when the request bundles many features/bugfixes/investigations that would degrade a single agent.
---

# Big Task

One long request containing many features, bugfixes, and investigations.
Too much for one agent to hold well.
This skill takes it from raw prompt to finished work across N parallel agents.

Requires running inside herdr: `test "${HERDR_ENV:-}" = 1`.
If the check fails, say so and stop.
The installed binary is the authority on CLI syntax: run `herdr agent`, `herdr pane`, `herdr tab`, or `herdr worktree` without a subcommand to print a group's usage, or `herdr --skill` for the full guide.

Seven phases, in order.
Do not skip ahead.
Phase 4 has a human gate.

## Phase 1 - Grill

Interview the user until the spec has no open questions.
Ask one question at a time with AskUserQuestion, and put your recommended answer first.
Each answer usually spawns follow-ups; keep going until a new round would produce nothing new.

Before each question, try to answer it yourself from the filesystem, git history, or the codebase.
Facts are looked up; only decisions go to the user.

The exit criterion: stop only when the spec you are about to write could be handed to an agent with **zero access to this conversation and zero ability to ask you anything**, and that agent would still make every decision the way the user wants.
A wrong assumption multiplied across N agents is N times the rework.

Ambiguities that must be resolved before you leave this phase:
- Scope boundaries between the parts (what is explicitly out of scope for each).
- Interfaces between the parts, and naming.
- Behavior on edge cases the user has not mentioned.
- Anything where two reasonable engineers would pick differently.
- What existing code must not change.
- Verification: what command proves each part works.

## Phase 2 - Spec

Write `specs/<YYYY-MM-DD>-<slug>/SPEC.md` in the repo.

Ensure the artifacts are gitignored.
Check `.gitignore` for `specs/`; if absent, append it to `.git/info/exclude` rather than editing the user's `.gitignore`.

The spec is the single source of truth for every spawned agent.
Structure:

```markdown
# <Title>

## Context
What this codebase is, what state it is in, what the user is trying to achieve.

## Decisions
Every decision settled during grilling, stated as a decision, not a discussion.
"Enums are stored as strings." not "We considered ints but chose strings."

## Work items
One section per discrete piece of work, each with:
- Goal
- Files/areas involved
- Explicit out-of-scope notes
- Verification command and expected result

## Conventions
Project-wide rules every agent must follow: style, toolchain, testing, what not to touch.

## Non-negotiables
Never commit or push. Never modify CHANGELOG.md or generated files.
Verify with real commands before claiming done.
```

Write full sentences, one per line.

## Phase 3 - Split

Decide N yourself from the work, not from a target number.

Sizing rules:
- One agent per cluster of work that shares files or a mental model.
- Split when two clusters touch disjoint file sets.
- Do not split work that would force two agents into the same file.
- Balance by wall-clock effort, not by file count.
- Investigation/research tasks parallelize freely - they only read.
- Practical ceiling is 5-6; beyond that coordination costs more than it saves.
- N=1 is a valid answer. Say so and just do the work.

Then decide isolation, per agent:

**Worktrees** when agents write to overlapping files, when the work is long-lived, when it needs isolated builds, or when you want independent branches to review separately.
**Same branch, same checkout** when file sets are provably disjoint, or when the work is read-only research.
Prefer the same checkout when the partition already makes it safe; it is less setup and less to merge.

Mixing is fine - research agents in the main checkout, implementers in worktrees.

Write `TASKS.md` beside the spec:

```markdown
# Tasks

## agent-1: <short name>
- Isolation: worktree `agent-1-<slug>` / same-branch
- Owns: <exact files or directories>
- Must not touch: <files owned by others>
- Depends on: <other agents, or none>
- Spec sections: <which parts of SPEC.md apply>
- Done when: <verification command and expected result>
```

The "Owns" and "Must not touch" lines are the collision-avoidance contract.
Be exact. Directories are fine; vague areas are not.

## Phase 4 - Gate, then fan out

**Stop and show the user** the split before spawning anything: N, each agent's scope, isolation choice, and the reasoning.
Wait for approval.
Skip this gate only if the user said to launch without asking.

### Worktree setup

For each worktree agent:

```bash
herdr worktree create --cwd <repo> --branch <branch-name> --label <agent-label> --no-focus
```

Then copy environment files, which git will not carry over.
Find them in the source repo:

```bash
git -C <repo> ls-files --others --ignored --exclude-standard \
  | grep -Ei '(^|/)\.env($|\.)|(^|/)\.dev\.vars$|\.local\.(toml|json|ya?ml)$|(^|/)\.envrc$'
```

Copy each match into the worktree, preserving its relative path and creating parent directories.
Never copy tracked files such as `.env.example`.
Report exactly what was copied, per worktree, so the user can spot a miss.

If the project needs more than env files - installs, migrations, generated clients - run those in the worktree too, and say what you ran.

### Layout

Lay panes out so the user can watch progress without hunting:
- Up to 3 agents: split them into the master's own tab (`herdr pane split --current --direction right|down --cwd <path> --no-focus`); master plus 3 is the comfortable maximum per tab.
- More than 3: group them into extra tabs of 3-4 panes each (`herdr tab create --cwd <path> --label <group> --no-focus`, then split within), named by component group; keep the master in the first tab.
- Worktree agents live in the workspace `herdr worktree create` made for them.

### Spawning

For each agent: get a pane in its working directory, start Claude in it, then prompt it.
Read pane and agent IDs from the JSON each command returns; never predict them.

```bash
herdr agent start <agent-name> --kind claude --pane <pane-id>
herdr agent prompt <agent-name> "<briefing>" --wait --until working
```

Agent names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents; make them meaningful.
Never pass `--permission-mode`.
Never instruct an agent to change its permission mode.

Each briefing must contain, inline:
- The absolute path to `SPEC.md` and an instruction to read it first.
- Its own section from `TASKS.md`, quoted in full.
- Its owned files and its forbidden files.
- The verification command it must run before claiming done.
- The reporting protocol below.

Give every agent this protocol verbatim:

> You are one of N agents on a shared spec, coordinated by a master agent.
> Read SPEC.md at <path> before doing anything.
> Stay strictly inside your owned files.
> If you discover that your work requires changing a file you do not own, or that your findings change another agent's scope, STOP and report it - do not make the change.
> Never commit and never push.
> Before you claim done, run your verification command and paste the real output.
> When you are done or blocked, state clearly: DONE or BLOCKED, followed by what happened.

## Phase 5 - Coordinate

You are now the master.
Stay in this loop until every agent is finished.
Do not end your turn while agents are running.

```bash
herdr agent list
herdr agent wait <agent-name> --timeout 600000          # idle, done, or blocked
herdr agent read <agent-name> --lines 60
herdr agent prompt <agent-name> "<instruction>"
```

Each cycle:
1. `herdr agent list` for statuses.
2. For each agent that is idle, blocked, or done: read its recent output.
3. Decide and act:
   - Question you can answer from the spec: answer it, do not bother the user.
   - Genuine ambiguity the spec missed: this is a grilling failure - ask the user, then patch SPEC.md so it stays authoritative.
   - Agent reports a cross-cutting change: this is the important case, below.
   - Agent claims done without pasted verification output: send it back to verify.
4. Relay meaningful progress and problems to the user as they happen, not as a dump at the end.
5. Wait on agents rather than hammering the socket in a tight loop.

### Cross-agent scope changes

When agent 1 reports "my fix will affect agent 2's area":

1. Read agent 1's reasoning and verify it against the code yourself.
2. Decide the new boundary. You own this decision, not the agents.
3. Update `SPEC.md` and `TASKS.md` to reflect it.
4. Message **both** agents immediately with the new boundary - the one gaining scope and the one losing it.
5. Tell the agent losing scope explicitly what to stop doing, and whether to revert anything already written.
6. Log the change so it reaches the report.

Never let two agents believe they own the same file.
When in doubt, pause one agent while the other lands its change.

If an agent dies or its pane is lost, respawn it with the same briefing plus a note about what already landed.

## Phase 6 - Verify and report

Verify each work item yourself against the spec's verification commands.
An agent's pasted output is a claim; your own run is the evidence.
For worktree agents, also confirm the branches merge cleanly or say that they do not.

Write `REPORT.md` beside the spec, and summarize it in your final message.

The report is for the user, not for you.

**Write only the outcome.**
"We store enums as strings."
Not "We first tried ints, but CloudKit rejected them, so we pivoted to strings."

**One exception:** when the implementation defies common sense, explain why, because the next reader will otherwise try to fix it.
"Enums are stored as strings because CloudKit's type system has no enum support and string round-trips are the only stable option."

Ban from the report: agent numbers, worktree names, phase names, "initially", "we pivoted", "after some investigation", token counts, timing.
The user does not care which agent did what.

```markdown
# <Title>

## What changed
Grouped by feature or area, never by agent.
Each entry: what now works, and where it lives.

## Issues found
Problems discovered along the way, whether or not they were fixed.
Mark each fixed or open.

## Decisions worth knowing
Only the non-obvious ones, each with its reason.

## Not done
Anything deferred or out of scope, and why.

## Verification
The commands that were run, and their actual results.
```

State plainly if something failed or is unverified.
Never claim done for work you did not see verified.

## Phase 7 - Teardown

Close an agent's pane (`herdr pane close <pane-id>`) only after its work is verified and captured in `REPORT.md`, so nothing is lost.
Close them one at a time, confirming each agent's work landed before closing it.
Leave worktrees in place for the user to merge or review; say which branches exist.
Leave nothing running when the task is done.

## Rules

- Never commit or push. Not you, not the agents.
- Never pass `--permission-mode` to a spawned agent, and never toggle it after launch.
- Never let an agent claim done without real verification output, and never report done without your own.
- Never end your turn with agents still running.
- The spec is authoritative: if an agent's question is answered there, answer it yourself.
- If grilling did not settle something, that is a bug in Phase 1 - fix the spec, do not paper over it in a briefing.
