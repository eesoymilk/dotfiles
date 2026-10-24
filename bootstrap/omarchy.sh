#!/usr/bin/env bash
# Bootstrap the dotfiles setup on Omarchy: install what Omarchy does not
# already ship, then link configs via ../install.sh. Normally invoked as
# `./install.sh --bootstrap`.
#
# Omarchy already provides the desktop (Hyprland, bar, launcher, lock, idle,
# notifications, screenshots, dictation) and most of the CLI set: nvim, tmux,
# herdr, lazygit, fzf, zoxide, eza, bat, fd, ripgrep, jq, tree-sitter,
# wl-clipboard, docker, the JetBrainsMono Nerd Font, and mise, which manages
# node, gh, claude, and codex. This script only fills the gaps, through
# Omarchy's own installers wherever one exists.
#
# Same step-runner contract as ubuntu.sh: no single tool can abort the run,
# failures are collected and reported, and the script exits non-zero when
# anything failed.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

STEPS_OK=()
STEPS_FAILED=()
step() {
	local title=$1 fn=$2 rc=0
	log "$title"
	set +e
	(
		set -eo pipefail
		"$fn"
	)
	rc=$?
	set -e
	if [ "$rc" -eq 0 ]; then
		STEPS_OK+=("$title")
	else
		STEPS_FAILED+=("$title")
		printf '\033[1;31m    ! %s failed (exit %s) - continuing\033[0m\n' "$title" "$rc"
	fi
}

# ------------------------------------------------------------ pacman packages
# Repo packages the shared configs need that Omarchy does not install.
# git-delta is the pager for git and lazygit.
install_packages() {
	omarchy pkg add zsh stow yazi git-delta
}

# ----------------------------------------------------------------- ghostty
# Omarchy's terminal installer: installs the package, seeds Omarchy's themed
# config, and makes ghostty the default for Super+Return.
install_ghostty() {
	omarchy install terminal ghostty
}

# ------------------------------------------------------------- mise tools
# Omarchy installs the agent CLIs through mise; make sure they are there
# (a no-op on a stock install). gh comes from here rather than pacman too.
install_mise_tools() {
	mise use -g claude@latest codex@latest gh@latest
}

# -------------------------------------------------------------- oh-my-posh
# Not packaged for Arch outside the AUR; use the official install script.
# Omarchy's starship only hooks into bash, and the zsh prompt stays shared
# with the mac and Ubuntu machines.
install_oh_my_posh() {
	if have oh-my-posh; then
		echo "  already present"
		return 0
	fi
	curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$BIN"
}

# ------------------------------------------------------------------- oxker
# AUR-only on Arch; official install script instead. It downloads into the
# current directory and installs to ~/.local/bin (which is $BIN), so run it
# from a temp dir to keep the droppings out of $PWD.
install_oxker() {
	if have oxker; then
		echo "  already present"
		return 0
	fi
	tmp=$(mktemp -d)
	(cd "$tmp" && curl -fsSL https://raw.githubusercontent.com/mrjackwills/oxker/main/install.sh | bash)
	rm -rf "$tmp"
}

# ------------------------------------------------------------------- link
link_dotfiles() {
	"$DOTFILES/install.sh"
}

# ----------------------------------------------------------- yazi packages
# yazi does not self-install its plugins: init.lua `require`s them outright.
# plugins/ and flavors/ are gitignored, so this must run after linking.
install_yazi_packages() {
	if ! have ya; then
		echo "  ya is not on PATH - the packages step must have failed" >&2
		return 1
	fi
	ya pkg install
}

# ------------------------------------------------------------ default shell
RELOGIN_MARKER="$(mktemp -u)"
set_default_shell() {
	LOGIN_SHELL=$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)
	if [ "$(basename "$LOGIN_SHELL")" != "zsh" ]; then
		if chsh -s "$(command -v zsh)"; then
			: >"$RELOGIN_MARKER"
		else
			echo "  chsh failed - falling back to a .bashrc exec"
			LINE='[ -z "$ZSH_VERSION" ] && [ -x "$(command -v zsh)" ] && exec zsh -l'
			grep -qF "$LINE" "$HOME/.bashrc" 2>/dev/null || echo "$LINE" >>"$HOME/.bashrc"
		fi
	else
		echo "  already zsh"
	fi
}

# ------------------------------------------------------------------- run
step "Packages (omarchy pkg add)" install_packages
step "Ghostty (omarchy install terminal)" install_ghostty
step "Claude Code, Codex, gh (mise)" install_mise_tools
step "oh-my-posh (official install script)" install_oh_my_posh
step "oxker (official install script)" install_oxker

hash -r

step "Linking dotfiles into \$HOME (stow)" link_dotfiles
step "yazi plugins and flavors (ya pkg install)" install_yazi_packages
step "Default shell" set_default_shell

# ------------------------------------------------------------------ verify
log "Verifying tools resolve on the shell PATH"
CHECK_PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/usr/local/bin:$PATH"
missing=""
for t in ghostty nvim tree-sitter tmux herdr zsh stow fd bat eza zoxide oh-my-posh yazi ya lazygit oxker delta git gh rg jq fzf mise claude codex; do
	PATH="$CHECK_PATH" command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
PATH="$CHECK_PATH" fzf --zsh >/dev/null 2>&1 || missing="$missing fzf(--zsh-unsupported)"
if [ -n "$missing" ]; then
	echo "  MISSING:$missing"
else
	echo "  all tools resolve"
fi

# ----------------------------------------------------------------- summary
log "Bootstrap summary"
for s in "${STEPS_OK[@]}"; do
	printf '  \033[1;32mok\033[0m      %s\n' "$s"
done
for s in "${STEPS_FAILED[@]}"; do
	printf '  \033[1;31mFAILED\033[0m  %s\n' "$s"
done
printf '\n  %d ok, %d failed\n' "${#STEPS_OK[@]}" "${#STEPS_FAILED[@]}"

if [ -e "$RELOGIN_MARKER" ]; then
	rm -f "$RELOGIN_MARKER"
	log "Log out and back in so the zsh login shell takes effect."
fi

if [ "${#STEPS_FAILED[@]}" -gt 0 ]; then
	printf '\n\033[1;31m%d step(s) failed.\033[0m Re-run to retry them;\n' "${#STEPS_FAILED[@]}"
	echo "everything that succeeded is skipped on the second pass."
	exit 1
fi
