#!/usr/bin/env bash
# Claude Code status line: reads the session JSON on stdin, prints one line.
#
# Width-aware by necessity. Claude Code captures stdout rather than handing the
# script a terminal, so `tput cols` sees nothing here; COLUMNS is exported for
# us instead (needs Claude Code 2.1.153+). Segments are assembled in priority
# order and the low-priority tail is dropped until the line fits, so a narrow
# split degrades to "model + context" instead of wrapping into the prompt.
set -uo pipefail

WIDTH=${COLUMNS:-80}
SEP=$' \033[90m│\033[0m '
SEP_W=3

C_RESET=$'\033[0m'
C_DIM=$'\033[90m'
C_MODEL=$'\033[1;36m'
C_DIR=$'\033[34m'
C_GIT=$'\033[35m'
C_DIRTY=$'\033[33m'
C_OK=$'\033[32m'
C_WARN=$'\033[33m'
C_CRIT=$'\033[1;31m'

json=$(cat)

if ! command -v jq >/dev/null 2>&1; then
	printf '%s\n' "${C_DIM}statusline: jq not installed${C_RESET}"
	exit 0
fi

# One jq call, not ten: the script runs on every assistant message.
# Joined on US (0x1f) rather than @tsv, because tab is an IFS *whitespace*
# character: bash collapses runs of it, so a single empty field (no agent, no
# effort) would silently shift every field after it by one.
IFS=$'\037' read -r MODEL PCT DIR FAST EFFORT AGENT COST DUR ADDED REMOVED < <(
	jq -r '[
		(.model.display_name // "?"),
		(if .context_window.used_percentage == null then -1
		 else (.context_window.used_percentage | floor) end),
		(.workspace.current_dir // .cwd // ""),
		(if .fast_mode then "1" else "" end),
		(.effort.level // ""),
		(.agent.name // ""),
		(.cost.total_cost_usd // 0),
		((.cost.total_duration_ms // 0) / 1000 | floor),
		(.cost.total_lines_added // 0),
		(.cost.total_lines_removed // 0)
	] | map(tostring) | join("\u001f")' <<<"$json"
)

# Visible width, in pure bash: forking sed per segment would be silly for a
# script this hot.
strip_ansi() {
	local s=$1
	while [[ $s =~ $'\033'\[[0-9\;]*m ]]; do s=${s//"${BASH_REMATCH[0]}"/}; done
	printf '%s' "$s"
}
vwidth() {
	local p
	p=$(strip_ansi "$1")
	printf '%s' "${#p}"
}

# ------------------------------------------------------------------ segments
# Each entry is "<long form>\t<short form>"; the short form is used when the
# long one would overflow, and the segment is dropped only if neither fits.
SEGS=()
add() { SEGS+=("$1"$'\t'"${2:-$1}"); }

# model, with the two flags that change what the model actually does
model="$MODEL"
[ -n "$EFFORT" ] && [ "$EFFORT" != "medium" ] && model="$model:$EFFORT"
[ -n "$FAST" ] && model="$model ⚡"
add "${C_MODEL}${model}${C_RESET}" "${C_MODEL}${MODEL}${C_RESET}"

[ -n "$AGENT" ] && add "${C_DIM}agent:${C_RESET}${AGENT}" "${AGENT}"

# context: the number worth glancing at, so it is second and never abbreviated
if [ "$PCT" -ge 0 ] 2>/dev/null; then
	if [ "$PCT" -ge 90 ]; then
		c=$C_CRIT
	elif [ "$PCT" -ge 70 ]; then
		c=$C_WARN
	else
		c=$C_OK
	fi
	add "${C_DIM}ctx${C_RESET} ${c}${PCT}%${C_RESET}" "${c}${PCT}%${C_RESET}"
else
	add "${C_DIM}ctx --${C_RESET}"
fi

# directory
if [ -n "$DIR" ]; then
	pretty=${DIR/#$HOME/\~}
	add "${C_DIR}${pretty}${C_RESET}" "${C_DIR}${DIR##*/}${C_RESET}"
fi

# git: cheap calls only, and the dirty check is cached because this script runs
# on every assistant message and `git status` on a large repo is not free.
if [ -n "$DIR" ] && [ -d "$DIR" ]; then
	branch=$(git -C "$DIR" symbolic-ref --quiet --short HEAD 2>/dev/null ||
		git -C "$DIR" rev-parse --short HEAD 2>/dev/null || true)
	if [ -n "$branch" ]; then
		cache="${TMPDIR:-/tmp}/.claude-statusline-git-$UID-$(cksum <<<"$DIR" | cut -d' ' -f1)"
		if [ -f "$cache" ] && [ $(($(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0))) -lt 3 ]; then
			dirty=$(cat "$cache")
		else
			dirty=""
			[ -n "$(git -C "$DIR" status --porcelain --untracked-files=no 2>/dev/null)" ] && dirty="*"
			printf '%s' "$dirty" >"$cache" 2>/dev/null || true
		fi
		add "${C_GIT}${branch}${C_DIRTY}${dirty}${C_RESET}" "${C_GIT}${branch:0:12}${C_DIRTY}${dirty}${C_RESET}"
	fi
fi

# churn and cost, the first things to go when the terminal is narrow
if [ "$ADDED" != "0" ] || [ "$REMOVED" != "0" ]; then
	add "${C_OK}+${ADDED}${C_RESET}/${C_CRIT}-${REMOVED}${C_RESET}"
fi

if [ "$DUR" -gt 0 ] 2>/dev/null; then
	if [ "$DUR" -ge 3600 ]; then
		t=$((DUR / 3600))h$((DUR % 3600 / 60))m
	elif [ "$DUR" -ge 60 ]; then
		t=$((DUR / 60))m$((DUR % 60))s
	else
		t=${DUR}s
	fi
	add "${C_DIM}${t}${C_RESET}"
fi

cost=$(printf '$%.2f' "$COST" 2>/dev/null || true)
[ -n "$cost" ] && [ "$cost" != '$0.00' ] && add "${C_DIM}${cost}${C_RESET}"

# ---------------------------------------------------------------- assemble
# Fill greedily: try each segment's long form, then its short form, and skip it
# if neither fits. Skipping rather than stopping means a narrow line still uses
# the space a dropped segment freed, and the order above decides what goes first.
line=""
used=0
for entry in "${SEGS[@]}"; do
	long=${entry%%$'\t'*}
	short=${entry#*$'\t'}
	for form in "$long" "$short"; do
		w=$(vwidth "$form")
		cost_w=$((used == 0 ? w : used + SEP_W + w))
		if [ "$cost_w" -le "$WIDTH" ]; then
			[ "$used" -eq 0 ] && line=$form || line="$line$SEP$form"
			used=$cost_w
			break
		fi
	done
done

# A context bar, but only with room left over for it - it is the first thing
# that should not push a real segment off the line.
if [ "$PCT" -ge 0 ] 2>/dev/null; then
	room=$((WIDTH - used - SEP_W - 2))
	if [ "$room" -ge 10 ]; then
		[ "$room" -gt 24 ] && room=24
		filled=$((PCT * room / 100))
		[ "$filled" -gt "$room" ] && filled=$room
		bar=""
		for ((i = 0; i < room; i++)); do
			if [ "$i" -lt "$filled" ]; then bar+="━"; else bar+="─"; fi
		done
		if [ "$PCT" -ge 90 ]; then
			c=$C_CRIT
		elif [ "$PCT" -ge 70 ]; then
			c=$C_WARN
		else
			c=$C_OK
		fi
		line="$line$SEP${c}${bar:0:filled}${C_DIM}${bar:filled}${C_RESET}"
	fi
fi

printf '%s\n' "$line"
