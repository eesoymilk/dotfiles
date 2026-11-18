#!/usr/bin/env bash
# Static checks for every tracked shell script and zsh config: shellcheck,
# shfmt (tabs, the repo style), and `zsh -n`, plus ruff, pyright, and pytest for
# the skill scripts, checked against the oldest python3 they run on (macOS's).
# Needs shellcheck, shfmt, zsh, and uv on PATH. Skills vendored from
# openai/skills keep upstream formatting and are skipped.
#
#   ./tests/lint.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit

VENDORED='^common/\.agents/skills/(gh-address-comments|gh-fix-ci|playwright|security-best-practices|security-threat-model)/'

mapfile -t scripts < <(
	git ls-files -z | xargs -0 grep -lE '^#!(/usr/bin/env |/bin/)(ba)?sh' | grep -vE "$VENDORED"
)
mapfile -t zsh_files < <(git ls-files '*.zsh' '*/.zshrc')

rc=0

echo "shellcheck (${#scripts[@]} scripts)"
shellcheck --severity=warning "${scripts[@]}" || rc=1

echo "shfmt"
shfmt --diff "${scripts[@]}" || rc=1

echo "zsh -n (${#zsh_files[@]} files)"
for f in "${zsh_files[@]}"; do
	zsh -n "$f" || rc=1
done

skill_scripts=(common/.agents/skills/route/scripts common/.agents/skills/wt-open/scripts common/.agents/skills/wt-cleanup/scripts common/.agents/skills/ship/scripts)
echo "python (${#skill_scripts[@]} script directories)"
ruff=(uvx ruff@0.17.3)
"${ruff[@]}" check --no-cache --target-version py39 --line-length 100 "${skill_scripts[@]}" || rc=1
"${ruff[@]}" format --no-cache --check --target-version py39 --line-length 100 "${skill_scripts[@]}" || rc=1
uvx pyright@1.1.414 --pythonversion 3.9 "${skill_scripts[@]}" || rc=1
PYTHONDONTWRITEBYTECODE=1 uvx pytest@9.2.0 -q -p no:cacheprovider "${skill_scripts[@]}" || rc=1

[ "$rc" -eq 0 ] && echo "LINT OK" || echo "LINT FAILED"
exit "$rc"
