#!/usr/bin/env bash
# Claude Code status line: reads the session JSON on stdin, prints one row when
# everything fits, otherwise two:
#
#   row 1, where:     model, agent, directory, git, session
#   row 2, resources: context, churn, cost
#
# Width-aware by necessity. Claude Code captures stdout rather than handing the
# script a terminal, so `tput cols` sees nothing here; COLUMNS is exported for
# us instead (needs Claude Code 2.1.153+). Each row is assembled in priority
# order and the low-priority tail is dropped until it fits, so a narrow split
# degrades to "model + directory" and "context" instead of wrapping.
set -uo pipefail

WIDTH=${COLUMNS:-80}
SEP=$' \033[90m│\033[0m '
SEP_W=3

C_RESET=$'\033[0m'
C_DIM=$'\033[90m'
C_MODEL=$'\033[1;36m'
C_NAME=$'\033[1m'
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

# One jq call, not twenty: the script runs on every assistant message.
# Joined on US (0x1f) rather than @tsv, because tab is an IFS *whitespace*
# character: bash collapses runs of it, so a single empty field (no agent, no
# effort) would silently shift every field after it by one.
IFS=$'\037' read -r MODEL EFFORT FAST AGENT STYLE SESSION DIR EXTRA_DIRS \
	PCT CTX_USED CTX_SIZE \
	COST ADDED REMOVED < <(
	jq -r '[
		(.model.display_name // "?"),
		(.effort.level // ""),
		(if .fast_mode then "1" else "" end),
		(.agent.name // ""),
		(.output_style.name // "default"),
		(.session_name // ""),
		(.workspace.current_dir // .cwd // ""),
		((.workspace.added_dirs // []) | length),
		(if .context_window.used_percentage == null then -1
		 else (.context_window.used_percentage | floor) end),
		((.context_window.current_usage // {}) | (.input_tokens // 0)
			+ (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)),
		(.context_window.context_window_size // 0),
		(.cost.total_cost_usd // 0),
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

# 104140 -> 104k, 1000000 -> 1M
tokens() {
	local n=$1
	if [ "$n" -ge 1000000 ]; then
		printf '%s.%sM' $((n / 1000000)) $((n % 1000000 / 100000)) | sed 's/\.0M$/M/'
	elif [ "$n" -ge 1000 ]; then
		printf '%sk' $((n / 1000))
	else
		printf '%s' "$n"
	fi
}

level_color() {
	if [ "$1" -ge 90 ]; then
		printf '%s' "$C_CRIT"
	elif [ "$1" -ge 70 ]; then
		printf '%s' "$C_WARN"
	else
		printf '%s' "$C_OK"
	fi
}

# Each entry is "<long form>\t<short form>"; the short form is used when the
# long one would overflow, and the segment is dropped only if neither fits.
SEGS=()
add() { SEGS+=("$1"$'\t'"${2:-$1}"); }

# Fill greedily: try each segment's long form, then its short form, and skip it
# if neither fits. Skipping rather than stopping means a narrow line still uses
# the space a dropped segment freed, and the order of add() calls decides what
# goes first. Sets LINE, and FULL=1 when every segment fit in its long form.
assemble() {
	local entry long short form w cost_w
	LINE=""
	USED=0
	FULL=1
	for entry in "${SEGS[@]}"; do
		long=${entry%%$'\t'*}
		short=${entry#*$'\t'}
		for form in "$long" "$short"; do
			w=$(vwidth "$form")
			cost_w=$((USED == 0 ? w : USED + SEP_W + w))
			if [ "$cost_w" -le "$WIDTH" ]; then
				[ "$USED" -eq 0 ] && LINE=$form || LINE="$LINE$SEP$form"
				USED=$cost_w
				[ "$form" != "$long" ] && FULL=0
				continue 2
			fi
		done
		FULL=0
	done
}

# ------------------------------------------------------------- row 1: where
# model, with the flags that change what the model actually does
model="$MODEL"
[ -n "$EFFORT" ] && model="$model ${C_RESET}${C_DIM}${EFFORT}${C_RESET}${C_MODEL}"
[ -n "$FAST" ] && model="$model ⚡"
add "${C_MODEL}${model}${C_RESET}" "${C_MODEL}${MODEL}${C_RESET}"

[ -n "$AGENT" ] && add "${C_DIM}agent ${C_RESET}${AGENT}" "${AGENT}"
[ "$STYLE" != "default" ] && add "${C_DIM}style ${C_RESET}${STYLE}"

if [ -n "$DIR" ]; then
	pretty=${DIR/#$HOME/\~}
	extra=""
	[ "$EXTRA_DIRS" -gt 0 ] 2>/dev/null && extra=" ${C_DIM}+${EXTRA_DIRS}${C_RESET}"
	add "${C_DIR}${pretty}${C_RESET}${extra}" "${C_DIR}${DIR##*/}${C_RESET}${extra}"
fi

# git: cheap calls only, and the dirty and ahead/behind checks are cached
# because this script runs on every assistant message and `git status` on a
# large repo is not free.
if [ -n "$DIR" ] && [ -d "$DIR" ]; then
	branch=$(git -C "$DIR" symbolic-ref --quiet --short HEAD 2>/dev/null ||
		git -C "$DIR" rev-parse --short HEAD 2>/dev/null || true)
	if [ -n "$branch" ]; then
		cache="${TMPDIR:-/tmp}/.claude-statusline-git-$UID-$(cksum <<<"$DIR" | cut -d' ' -f1)"
		if [ -f "$cache" ] && [ $((EPOCHSECONDS - $(stat -c %Y "$cache" 2>/dev/null || echo 0))) -lt 3 ]; then
			read -r dirty ahead behind <"$cache"
		else
			dirty="-"
			[ -n "$(git -C "$DIR" status --porcelain --untracked-files=no 2>/dev/null)" ] && dirty="*"
			read -r behind ahead < <(git -C "$DIR" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0 0")
			printf '%s %s %s\n' "$dirty" "$ahead" "$behind" >"$cache" 2>/dev/null || true
		fi
		[ "$dirty" = "-" ] && dirty=""
		sync=""
		[ "${ahead:-0}" -gt 0 ] && sync+=" ${C_OK}↑${ahead}${C_RESET}"
		[ "${behind:-0}" -gt 0 ] && sync+=" ${C_WARN}↓${behind}${C_RESET}"
		add "${C_GIT}${branch}${C_DIRTY}${dirty}${C_RESET}${sync}" \
			"${C_GIT}${branch:0:12}${C_DIRTY}${dirty}${C_RESET}${sync}"
	fi
fi

# the session name is the least useful for orientation, so it goes last
[ -n "$SESSION" ] && add "${C_NAME}${SESSION}${C_RESET}" "${C_NAME}${SESSION:0:20}…${C_RESET}"

WHERE=("${SEGS[@]}")
SEGS=()

# --------------------------------------------------------- row 2: resources
# context: a bar plus the real token count, never dropped
if [ "$PCT" -ge 0 ] 2>/dev/null; then
	c=$(level_color "$PCT")
	filled=$((PCT * 12 / 100))
	[ "$filled" -gt 12 ] && filled=12
	bar=""
	for ((i = 0; i < 12; i++)); do
		if [ "$i" -lt "$filled" ]; then bar+="━"; else bar+="─"; fi
	done
	bar="${c}${bar:0:filled}${C_DIM}${bar:filled}${C_RESET}"
	size=""
	[ "$CTX_SIZE" -gt 0 ] && size="${C_DIM}$(tokens "$CTX_USED")/$(tokens "$CTX_SIZE")${C_RESET}"
	add "${C_DIM}ctx${C_RESET} ${bar} ${c}${PCT}%${C_RESET} ${size}" "${C_DIM}ctx${C_RESET} ${c}${PCT}%${C_RESET}"
else
	add "${C_DIM}ctx --${C_RESET}"
fi

if [ "$ADDED" != "0" ] || [ "$REMOVED" != "0" ]; then
	add "${C_OK}+${ADDED}${C_RESET} ${C_CRIT}-${REMOVED}${C_RESET}"
fi

cost=$(printf '$%.2f' "$COST" 2>/dev/null || true)
[ -n "$cost" ] && [ "$cost" != '$0.00' ] && add "${C_DIM}${cost}${C_RESET}"

RESOURCES=("${SEGS[@]}")

# ------------------------------------------------------------------ output
SEGS=("${WHERE[@]}" "${RESOURCES[@]}")
assemble
if [ "$FULL" -eq 1 ]; then
	printf '%s\n' "$LINE"
	exit 0
fi

SEGS=("${WHERE[@]}")
assemble
printf '%s\n' "$LINE"
SEGS=("${RESOURCES[@]}")
assemble
printf '%s\n' "$LINE"
