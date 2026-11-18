---
name: route
description: Pick the harness (Claude Code, Codex, or pi), model, and effort for an agent you are about to delegate a task to, by task difficulty and the quota left on each subscription, and confirm the pick with the user. Use before starting any agent in herdr (wt-open, fleet), or when the user asks which model or harness a task should get, or runs /route.
---

# Route

Send each task to the cheapest agent that will do it well, and spend the quota that has the most room.

## 1. Read the table and the quota

```bash
~/.agents/skills/route/scripts/route.py status
```

It prints JSON:

- `tiers`: for each tier, the options with `kind`, `model`, `effort`, the native `args` to launch them with, and whether they are `available` (installed, and for pi, the local llama.cpp server is up).
- `usage`: for `claude` and `codex`, the percent `left` in the tighter of the 5-hour and weekly windows, each window on its own, and `age_minutes` since the data was recorded.
  `null` means no data: Claude Code records it only while a session renders its status line, and Codex only while a session runs.
  A window whose reset time has passed counts as full, so old data is still right about windows that have reset.
- `prefer`: the harness with clearly more quota left, or `null` when neither stands out.

## 2. Classify the task

Pick the lowest tier that will do the task well; a failed cheap attempt costs more than the right tier.

| Tier | The task |
| --- | --- |
| `max` | Architecture, cross-cutting refactors, subtle concurrency or security bugs, or a spec with open questions the agent must settle well. |
| `normal` | A typical feature or bugfix that needs exploring the codebase and making judgment calls. |
| `easy` | Coding only: what to change and where is already settled, and the agent just has to write it. |
| `light` | Mechanical edits, renames, doc tweaks, searching or summarizing code. |
| `trivial` | Running commands and reporting the output: tests, lint, builds, git queries. No code reasoning. |

The models behind each tier live in `TIERS` in `scripts/route.py`.

Judge by what the agent must decide, not by how much it must type.
If the briefing settles every decision, the task drops a tier; if it leaves design open, it rises one.

## 3. Pick the harness within the tier

- If `prefer` is set, use it.
- If both harnesses have data and neither is preferred, both have room: pick the one that suits the task, such as Codex for long autonomous implementation and Claude for work that leans on judgment or prose, and spread parallel agents across both.
- A harness with no data has not been used lately, so treat it as having room.
- Never pick a harness under 10% left; drop to the other one, or to the tier below if that still fits the task.
- If the option is not `available`, use the other option in the tier, or for `trivial`, use `light`.

## 4. Confirm with the user

Skip this step only if the user already named the harness and model.
Otherwise ask once before launching anything, with AskUserQuestion where the harness has it or else in chat, and wait for the answer:

- Put your pick first, marked "(Recommended)", with its tier and a one-line reason that cites the quota, such as "normal tier; Codex has 80% left, Claude 35%".
- Add the other harness in the same tier, and the tier above or below, whichever is the likelier correction.

For several agents at once, as in fleet, show the whole assignment instead and let the user change any line of it.

## 5. Launch with the native args

Pass the chosen option's `kind` as the harness and its `args` as the agent's own arguments, after `--`:

```bash
herdr agent start <name> --kind <kind> --pane <pane> -- <args...>
~/.agents/skills/wt-open/scripts/wt_open.py --branch <branch> --kind <kind> -- <args...> <<'BRIEF'
```

For a harness, model, or effort the user names that is not in the table, get the args from the script, which validates the effort:

```bash
~/.agents/skills/route/scripts/route.py args --kind <claude|codex|pi> --model <model> [--effort <level>]
```

These args only choose the model and effort.
Never add permission, approval, or sandbox flags to them.

When reporting the launch, name the tier, harness, model, and effort.
