# Soymilk's agent instructions

Common instructions for soymilk's agents across all scenarios.

## Guidelines

- Never use the em dash "—". Use plain dash "-" instead.
- Never commit or push unless explicitly asked. If a task seems to call for a commit or push, stop and ask first; never assume approval for one carries over to the next.
- Never auto-add your agent name as co-author in commit messages.
- Never modify CHANGELOG.md or auto-generated files.
- Comments and docstrings say only what the code does or why it must be this way, in terms of the code and the system. Code must be indistinguishable from what the user would have written by hand.
  - Never put history or provenance in code, comments, docstrings, or test names: no incident or alert numbers, PR or issue numbers, Jira keys, dates, people's names, Slack threads, "as discussed", "per user request", "added by Claude", or references to the conversation, the review, or the agent. That history belongs in the commit message, PR, or ticket.
  - This rule beats "match existing style": if the file already has such comments, do not copy them, and leave the existing ones alone.
  - Before reporting a change done, grep the added lines of the diff (e.g. `git diff -U0 | grep '^+' | grep -E '[Ii]ncident|[Pp]ager[Dd]uty|[Jj]ira|#[0-9]+|\b[A-Z]{2,}-[0-9]+\b|20[0-9]{2}-[0-9]{2}'`) and rewrite every hit as plain rationale.
- In long Markdown files, put each full sentence on its own line.
- Prefer quality, simplicity, robustness, and maintainability over development cost.
- Bug fixes: reproduce the bug E2E as an end user would hit it before fixing.
- Be picky about UI polish and engineering excellence (lint, flaky tests): fix small issues you spot in files you are already touching, and report the rest instead of fixing them.
- Minimum code that solves the problem. No speculative features or single-use abstractions.
- Touch only what the request requires. No drive-by refactors; match existing style.
- Judge a change by its impact, not its size. Before proposing it, state what it reaches, what it newly does on its own, and how to undo it, then shrink it to the narrowest scope that solves the problem.
- Evaluate a change against what is already running, not in isolation. Two harmless pieces can combine into new behavior.
- When the obvious fix overrides, works around, or removes someone else's design or decision, stop and surface the gap to its owner before building the alternative.
- Label inferences as inferences. Never state an unverified cause, number, or claim as fact in anything other people will read.
- Before choosing how to install, configure, or integrate a third-party tool, read its official installation docs yourself and follow the recommended method. If you deviate, say so up front with the recommendation and your reason, and let the user decide.
- Clean up orphans your change created; leave pre-existing dead code alone.
- Verify before claiming done: run tests/lint, state actual results.
- Python: uv, full type hints, ruff, pyright, pytest.
- TypeScript: pnpm, strictest tsconfig, zod, vitest.
- Never override permission, approval, or sandbox settings on agents you spawn, at launch or after; the machine's config sets the intended defaults.
- Pick a model for every subagent or delegated agent by the work it does, and set it explicitly (in Claude Code, the Agent tool's `model`); a model the user names wins.
  - Opus: planning, design, review, and debugging or features that still leave decisions open.
  - Sonnet: coding where what to change and where is already settled.
  - Haiku: searching, reading, or summarizing code, mechanical edits, and running commands to report their output.
  - Never use a fork for work meant for a cheaper model: a fork always runs on the parent's model.
