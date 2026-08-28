#!/usr/bin/env bash
# Bootstrap the dotfiles setup on Arch: install every tool, then link
# configs via ../install.sh. Normally invoked as `./install.sh --bootstrap`.
#
# Same step-runner contract as ubuntu.sh: no single tool can abort the run,
# failures are collected and reported, and the script exits non-zero when
# anything failed.
#
# SKIP_DESKTOP=1 skips the Hyprland desktop stack (useful in containers).
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
# Everything the shared configs expect that lives in the official repos.
install_pacman() {
	sudo pacman -Syu --needed --noconfirm \
		zsh stow tmux git curl wget unzip tar base-devel \
		fd bat ripgrep jq \
		fzf zoxide eza yazi neovim tree-sitter-cli \
		lazygit github-cli git-delta \
		wl-clipboard \
		ttf-jetbrains-mono-nerd \
		ghostty
}

# ------------------------------------------------------- hyprland desktop stack
# wlogout is AUR-only; install it with paru/yay when one is present, otherwise
# report it as manual work instead of failing the step.
install_desktop() {
	if [ "${SKIP_DESKTOP:-0}" = 1 ]; then
		echo "  SKIP_DESKTOP=1 - skipping"
		return 0
	fi
	sudo pacman -S --needed --noconfirm \
		hyprland hypridle hyprlock hyprpaper waybar wofi
	if have paru; then
		paru -S --needed --noconfirm wlogout
	elif have yay; then
		yay -S --needed --noconfirm wlogout
	else
		echo "  wlogout is AUR-only and no AUR helper found - install it manually"
	fi
}

# -------------------------------------------------------------- oh-my-posh
# AUR-only on Arch, so use the official install script like ubuntu.sh does.
install_oh_my_posh() {
	if have oh-my-posh; then
		echo "  already present"
		return 0
	fi
	curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$BIN"
}

# -------------------------------------------------------------- lazydocker
# AUR-only on Arch; official install script instead.
install_lazydocker() {
	if have lazydocker; then
		echo "  already present"
		return 0
	fi
	curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh |
		DIR="$BIN" bash
}

# --------------------------------------------------------------------- nvm
# Official (nvm README): the upstream install script. PROFILE=/dev/null stops
# it appending to ~/.zshrc, which is a symlink into this repo; .zshrc already
# sources nvm itself.
install_nvm() {
	if [ -d "$HOME/.nvm" ]; then
		echo "  already present"
		return 0
	fi
	curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh |
		PROFILE=/dev/null bash
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
		echo "  ya is not on PATH - the pacman step must have failed" >&2
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
step "pacman packages" install_pacman
step "Hyprland desktop stack" install_desktop
step "oh-my-posh (official install script)" install_oh_my_posh
step "lazydocker (official install script)" install_lazydocker
step "nvm (official install script)" install_nvm

hash -r

step "Linking dotfiles into \$HOME (stow)" link_dotfiles
step "yazi plugins and flavors (ya pkg install)" install_yazi_packages
step "Default shell" set_default_shell

# ------------------------------------------------------------------ verify
log "Verifying tools resolve on the shell PATH"
CHECK_PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
missing=""
for t in nvim tree-sitter tmux zsh stow fd bat eza zoxide oh-my-posh yazi ya lazygit lazydocker delta git gh rg jq fzf; do
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
