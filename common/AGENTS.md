# Soymilk's agent instructions

Common instructions for soymilk's agents across all scenarios.

## Guidelines

- Never use the em dash "—". Use plain dash "-" instead.
- Never commit or push unless explicitly asked. If a task seems to call for a commit or push, stop and ask first; never assume approval for one carries over to the next.
- Never auto-add your agent name as co-author in commit messages.
- Never modify CHANGELOG.md or auto-generated files.
- Never leave traces of the AI session in code or comments: no dated decision notes ("Lead decision 2026-08-31"), no "as discussed", no "per user request", no "added by Claude", no references to the conversation, the PR review, or the agent. Comments describe what the code does or why it must be this way, nothing else. Code must be indistinguishable from what the user would have written by hand.
- In long Markdown files, put each full sentence on its own line.
- Prefer quality, simplicity, robustness, and maintainability over development cost.
- Bug fixes: reproduce the bug E2E as an end user would hit it before fixing.
- Be picky about UI polish and engineering excellence (lint, flaky tests): fix small issues you spot in files you are already touching, and report the rest instead of fixing them.
- Minimum code that solves the problem. No speculative features or single-use abstractions.
- Touch only what the request requires. No drive-by refactors; match existing style.
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
