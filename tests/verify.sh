#!/usr/bin/env bash
# Assert the installed state a fresh machine should end up in after
# `./install.sh --bootstrap`. Run inside the test containers, but safe to run
# on a real machine too. Hard assertions: any failure fails the run.
set -uo pipefail

FAILED=0
pass() { printf '  \033[1;32mok\033[0m      %s\n' "$1"; }
fail() {
	printf '  \033[1;31mFAILED\033[0m  %s\n' "$1"
	FAILED=1
}

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
Darwin) OS_PKG=macos ;;
*)
	# shellcheck disable=SC1091
	. /etc/os-release
	case "${ID:-} ${ID_LIKE:-}" in
	*arch*) OS_PKG=omarchy ;;
	*) OS_PKG=ubuntu ;;
	esac
	;;
esac
echo "Verifying against packages: common + $OS_PKG"

# ------------------------------------------------------------------ symlinks
link_into_repo() {
	local target="$1" label="$2"
	local resolved
	resolved="$(readlink -f "$target" 2>/dev/null || true)"
	if [ -n "$resolved" ] && [ -e "$target" ] && [[ "$resolved" == "$DOTFILES"/* ]]; then
		pass "$label -> ${resolved#"$DOTFILES"/}"
	else
		fail "$label (resolves to: ${resolved:-nothing})"
	fi
}

echo
echo "Symlinks:"
link_into_repo "$HOME/.zshrc" "~/.zshrc"
link_into_repo "$HOME/AGENTS.md" "~/AGENTS.md"
link_into_repo "$HOME/.config/nvim" "~/.config/nvim"
link_into_repo "$HOME/.config/tmux/tmux.conf" "~/.config/tmux/tmux.conf"
link_into_repo "$HOME/.config/ohmyposh" "~/.config/ohmyposh"
link_into_repo "$HOME/.config/zsh/pre.zsh" "~/.config/zsh/pre.zsh (from $OS_PKG)"
link_into_repo "$HOME/.config/zsh/post.zsh" "~/.config/zsh/post.zsh (from $OS_PKG)"
link_into_repo "$HOME/.claude/agents" "~/.claude/agents"
link_into_repo "$HOME/.claude/CLAUDE.md" "~/.claude/CLAUDE.md"
link_into_repo "$HOME/.local/bin/tmux-sessionizer" "~/.local/bin/tmux-sessionizer"

# ~/.agents/skills is a real dir holding machine-local skills too, so assert
# each repo-provided skill rather than the directory. The first two are shared
# with Claude Code through ~/.claude/skills; the rest are Codex-only.
SHARED_SKILLS="brainstorm big-task"
CODEX_SKILLS="gh-address-comments gh-fix-ci playwright security-best-practices security-threat-model"
for s in $SHARED_SKILLS $CODEX_SKILLS; do
	link_into_repo "$HOME/.agents/skills/$s" "~/.agents/skills/$s"
done
for s in $SHARED_SKILLS; do
	link_into_repo "$HOME/.claude/skills/$s" "~/.claude/skills/$s"
done
for s in $CODEX_SKILLS; do
	if [ -e "$HOME/.claude/skills/$s" ] || [ -L "$HOME/.claude/skills/$s" ]; then
		fail "~/.claude/skills/$s is absent (Codex-only skill)"
	else
		pass "~/.claude/skills/$s is absent (Codex-only skill)"
	fi
done

link_into_repo "$HOME/.codex/AGENTS.md" "~/.codex/AGENTS.md"
link_into_repo "$HOME/.codex/config.toml" "~/.codex/config.toml"
codex_agents=("$DOTFILES"/common/.codex/agents/*.toml)
if [ -e "${codex_agents[0]}" ]; then
	for f in "${codex_agents[@]}"; do
		link_into_repo "$HOME/.codex/agents/$(basename "$f")" "~/.codex/agents/$(basename "$f")"
	done
else
	fail "common/.codex/agents contains at least one agent TOML"
fi

if [ -x "$HOME/.local/bin/tmux-sessionizer" ]; then
	pass "tmux-sessionizer is executable"
else
	fail "tmux-sessionizer is executable"
fi

# These must stay real directories, never symlinks into the repo: apps write
# runtime state next to the stowed files (Codex keeps auth.json and sqlite
# databases in ~/.codex, both CLIs keep machine-local skills).
for d in .config .claude .claude/skills .agents .agents/skills .codex .codex/agents; do
	if [ -d "$HOME/$d" ] && [ ! -L "$HOME/$d" ]; then
		pass "~/$d is a real directory"
	else
		fail "~/$d is a real directory"
	fi
done

if [ "$OS_PKG" = omarchy ]; then
	# Omarchy owns ghostty's config (its font and text-size commands sed it),
	# so it must stay a real file that includes the stowed overrides.
	GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
	if [ -f "$GHOSTTY_CONFIG" ] && [ ! -L "$GHOSTTY_CONFIG" ] &&
		grep -qxF 'config-file = ?user.conf' "$GHOSTTY_CONFIG"; then
		pass "~/.config/ghostty/config is Omarchy's and includes user.conf"
	else
		fail "~/.config/ghostty/config is Omarchy's and includes user.conf"
	fi
	link_into_repo "$HOME/.config/ghostty/user.conf" "~/.config/ghostty/user.conf"
	link_into_repo "$HOME/.config/omarchy/hooks/theme-set.d/wallpaper" "wallpaper theme-set hook"
	link_into_repo "$HOME/.config/omarchy/wallpapers" "~/.config/omarchy/wallpapers"
else
	link_into_repo "$HOME/.config/ghostty/config" "~/.config/ghostty/config"
fi

# --------------------------------------------------------------------- tools
echo
echo "Tools on the shell PATH:"
CHECK_PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.fzf/bin:/opt/nvim/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
for t in nvim tree-sitter tmux zsh stow fd bat eza zoxide oh-my-posh yazi ya lazygit delta git gh rg jq fzf claude codex; do
	if PATH="$CHECK_PATH" command -v "$t" >/dev/null 2>&1; then
		pass "$t"
	else
		fail "$t"
	fi
done
if PATH="$CHECK_PATH" fzf --zsh >/dev/null 2>&1; then
	pass "fzf supports --zsh"
else
	fail "fzf supports --zsh"
fi

# ----------------------------------------------------------------- zsh boots
echo
echo "Interactive zsh starts cleanly (zinit installs plugins on first run):"
if PATH="$CHECK_PATH" zsh -ic 'exit 0' >/dev/null 2>&1; then
	pass "zsh -ic 'exit 0'"
else
	fail "zsh -ic 'exit 0'"
fi

echo
if [ "$FAILED" -ne 0 ]; then
	echo "VERIFY FAILED"
	exit 1
fi
echo "VERIFY OK"
