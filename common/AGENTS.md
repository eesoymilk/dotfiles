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
- Be picky about UI polish and engineering excellence (lint, flaky tests) - fix issues you spot even if unrelated.
- Minimum code that solves the problem. No speculative features or single-use abstractions.
- Touch only what the request requires. No drive-by refactors; match existing style.
- Clean up orphans your change created; leave pre-existing dead code alone.
- Verify before claiming done: run tests/lint, state actual results.
- Python: uv, full type hints, ruff, pyright, pytest.
- TypeScript: pnpm, strictest tsconfig, zod, vitest.
- When spawning agent instances (herdr or otherwise), never override the user's permission setup from the command line or after launch; the global config already sets the intended default - leave it.
  - Claude Code: never pass --permission-mode and never toggle the permission mode after launch (no shift+tab, no /permissions). The global default is "auto" mode. Do NOT switch spawned agents to acceptEdits.
  - Codex: launch plain `codex`. Never pass --ask-for-approval, --sandbox, --approve-for-me, --dangerously-bypass-approvals-and-sandbox, or -c overrides for approval_policy, approvals_reviewer, or sandbox_mode; ~/.codex/config.toml sets on-request approval with Auto-review and a workspace-write sandbox.
