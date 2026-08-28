#!/usr/bin/env bash
# Bootstrap the dotfiles setup on macOS: install every tool via Homebrew,
# then link configs via ../install.sh. Normally invoked as
# `./install.sh --bootstrap`.
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

# --------------------------------------------------------------- homebrew
# Official (brew.sh): the upstream install script.
install_brew() {
	if have brew || [ -x /opt/homebrew/bin/brew ]; then
		echo "  already present"
	else
		NONINTERACTIVE=1 /bin/bash -c \
			"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	fi
	eval "$(/opt/homebrew/bin/brew shellenv)"
}

# ------------------------------------------------------------ brew formulae
install_formulae() {
	eval "$(/opt/homebrew/bin/brew shellenv)"
	brew install \
		stow tmux fzf zoxide eza bat fd ripgrep jq \
		gh lazygit lazydocker git-delta \
		neovim yazi oh-my-posh tree-sitter
}

# --------------------------------------------------------------- brew casks
install_casks() {
	eval "$(/opt/homebrew/bin/brew shellenv)"
	brew install --cask ghostty aerospace font-jetbrains-mono-nerd-font
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
install_yazi_packages() {
	eval "$(/opt/homebrew/bin/brew shellenv)"
	if ! have ya; then
		echo "  ya is not on PATH - the yazi install must have failed" >&2
		return 1
	fi
	ya pkg install
}

# ------------------------------------------------------------------- run
step "Homebrew (official install script)" install_brew
step "brew formulae" install_formulae
step "brew casks (ghostty, aerospace, nerd font)" install_casks
step "nvm (official install script)" install_nvm

hash -r

step "Linking dotfiles into \$HOME (stow)" link_dotfiles
step "yazi plugins and flavors (ya pkg install)" install_yazi_packages

# ------------------------------------------------------------------ verify
log "Verifying tools resolve on the shell PATH"
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
CHECK_PATH="$HOME/.local/bin:$PATH"
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

log "Then:"
cat <<'EOF'
  1. zinit auto-installs plugins on first zsh launch (wait a few seconds)
  2. Start tmux once; TPM auto-clones and installs plugins
  3. nvm install --lts
  4. Set your terminal font to "JetBrainsMono Nerd Font"
EOF

if [ "${#STEPS_FAILED[@]}" -gt 0 ]; then
	printf '\n\033[1;31m%d step(s) failed.\033[0m Re-run to retry them;\n' "${#STEPS_FAILED[@]}"
	echo "everything that succeeded is skipped on the second pass."
	exit 1
fi
