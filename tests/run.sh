#!/usr/bin/env bash
# Run the E2E docker tests: fresh Ubuntu and Arch containers each run the
# real bootstrap and then assert the resulting state.
#
#   ./tests/run.sh            run both
#   ./tests/run.sh ubuntu     run one
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

targets=("$@")
[ "${#targets[@]}" -eq 0 ] && targets=(ubuntu arch)

declare -A results
rc=0
for os in "${targets[@]}"; do
	echo
	echo "==============================================================="
	echo "  E2E: $os"
	echo "==============================================================="
	if docker build --progress=plain -f "tests/Dockerfile.$os" -t "dotfiles-test-$os" .; then
		results[$os]=ok
	else
		results[$os]=FAILED
		rc=1
	fi
done

echo
echo "Results:"
for os in "${targets[@]}"; do
	printf '  %-8s %s\n' "$os" "${results[$os]}"
done
exit "$rc"
