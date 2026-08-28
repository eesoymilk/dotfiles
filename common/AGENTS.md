# Soymilk's agent instructions

Common instructions for soymilk's agents across all scenarios.

## Guidelines

- Never use the em dash "—". Use plain dash "-" instead.
- Never commit unless explicitly asked.
- Never auto-add your agent name as co-author in commit messages.
- Never modify CHANGELOG.md or auto-generated files.
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
- When spawning claude instances (herdr or otherwise): never pass --permission-mode and never toggle the permission mode after launch (no shift+tab, no /permissions). The global default is "auto" mode - leave it. Do NOT switch spawned agents to acceptEdits.
