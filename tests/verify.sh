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
	*arch*) OS_PKG=arch ;;
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
link_into_repo "$HOME/.config/tmux" "~/.config/tmux"
link_into_repo "$HOME/.config/ghostty/config" "~/.config/ghostty/config"
link_into_repo "$HOME/.config/ohmyposh" "~/.config/ohmyposh"
link_into_repo "$HOME/.config/zsh/pre.zsh" "~/.config/zsh/pre.zsh (from $OS_PKG)"
link_into_repo "$HOME/.config/zsh/post.zsh" "~/.config/zsh/post.zsh (from $OS_PKG)"
link_into_repo "$HOME/.claude/agents" "~/.claude/agents"
# ~/.claude/skills may be a real dir holding machine-local skills; assert a
# repo-provided skill resolves rather than the directory itself.
link_into_repo "$HOME/.claude/skills/big-task" "~/.claude/skills/big-task"
link_into_repo "$HOME/.claude/CLAUDE.md" "~/.claude/CLAUDE.md"
link_into_repo "$HOME/.local/bin/tmux-sessionizer" "~/.local/bin/tmux-sessionizer"

if [ -x "$HOME/.local/bin/tmux-sessionizer" ]; then
	pass "tmux-sessionizer is executable"
else
	fail "tmux-sessionizer is executable"
fi

# ~/.config must stay a real directory, never a symlink into the repo.
if [ -d "$HOME/.config" ] && [ ! -L "$HOME/.config" ]; then
	pass "~/.config is a real directory"
else
	fail "~/.config is a real directory"
fi

if [ "$OS_PKG" = arch ]; then
	link_into_repo "$HOME/.config/ghostty/os.conf" "~/.config/ghostty/os.conf (arch overrides)"
	link_into_repo "$HOME/.config/hypr" "~/.config/hypr"
fi

# --------------------------------------------------------------------- tools
echo
echo "Tools on the shell PATH:"
CHECK_PATH="$HOME/.local/bin:$HOME/.fzf/bin:/opt/nvim/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
for t in nvim tree-sitter tmux zsh stow fd bat eza zoxide oh-my-posh yazi ya lazygit delta git gh rg jq fzf; do
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
