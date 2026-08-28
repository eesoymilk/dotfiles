#!/usr/bin/env bash
# Bootstrap the dotfiles setup on Ubuntu: install every tool, then link
# configs via ../install.sh. Normally invoked as `./install.sh --bootstrap`.
# Idempotent: safe to re-run. Assumes sudo is available.
#
# Every tool here is installed the way its own documentation prescribes.
# Where a hand-rolled fetch would be shorter it is still avoided: upstream
# changes asset names and layouts, and following the documented path is what
# keeps this script working a year from now.
#
# No single tool can abort the run. Each section is a step; a step that fails
# is recorded and the rest still install, so one unreachable mirror costs you
# that tool rather than the whole machine. The summary at the end names what
# failed, and the script exits non-zero when anything did.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------- step runner
# The subshell re-enables errexit for the step body. Bash suppresses errexit
# inside any command whose status is tested, so the obvious `install_x || rc=$?`
# would run a step straight past its own first failure - a failed curl would
# continue into the tar that unpacks what it never downloaded. Toggling errexit
# off around an *untested* subshell is what keeps the step honest while still
# handing the status back here.
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

# ----------------------------------------------------------------- platform
# Each project names its release assets differently for the same machine, so
# resolve every spelling once here instead of hardcoding x86_64 throughout.
# This one does abort: every download below depends on it.
case "$(uname -m)" in
x86_64)
	NVIM_ARCH=x86_64
	TS_ARCH=x64    # tree-sitter
	GO_ARCH=x86_64 # lazygit
	DEB_ARCH=amd64 # delta
	;;
aarch64 | arm64)
	NVIM_ARCH=arm64
	TS_ARCH=arm64
	GO_ARCH=arm64
	DEB_ARCH=arm64
	;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac
log "Detected $(uname -m) ($(. /etc/os-release && echo "$PRETTY_NAME"))"

# -------------------------------------------------------------- apt packages
install_apt() {
	sudo apt-get update -qq
	sudo apt-get install -y --no-install-recommends \
		zsh stow tmux git curl wget unzip tar gzip ca-certificates gnupg \
		build-essential pkg-config \
		fd-find bat ripgrep jq file \
		wl-clipboard \
		python3 python3-venv

	# Ubuntu renames both binaries to avoid collisions with older packages.
	# The `cat=bat` alias in .zshrc and the `fd` call in tmux-sessionizer expect
	# the upstream names, so bridge them.
	[ -e "$BIN/fd" ] || ln -sf "$(command -v fdfind)" "$BIN/fd"
	[ -e "$BIN/bat" ] || ln -sf "$(command -v batcat)" "$BIN/bat"
}

# ------------------------------------------------------------------- neovim
# Official (neovim INSTALL.md): extract the release tarball under /opt.
# Upstream's own PATH line is /opt/nvim-linux-<arch>/bin, which would bake the
# architecture into .zshrc. Symlink a stable /opt/nvim so the shared config
# stays arch-agnostic.
install_neovim() {
	if [ ! -x "/opt/nvim-linux-$NVIM_ARCH/bin/nvim" ]; then
		tmp=$(mktemp -d)
		curl -fsSL -o "$tmp/nvim.tar.gz" \
			"https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$NVIM_ARCH.tar.gz"
		sudo rm -rf "/opt/nvim-linux-$NVIM_ARCH"
		sudo tar -C /opt -xzf "$tmp/nvim.tar.gz"
		rm -rf "$tmp"
	else
		echo "  already present"
	fi
	sudo ln -sfn "/opt/nvim-linux-$NVIM_ARCH" /opt/nvim
}

# -------------------------------------------------------- tree-sitter CLI
# Required by nvim-treesitter's `main` branch, which is the only branch that
# supports Neovim 0.12; `master` is frozen and says so in its own README.
# Upstream's instruction is to install the CLI from a package manager rather
# than npm, but Ubuntu ships 0.20.8 and main needs >= 0.26.1, so this takes the
# official release binary - the same documented-path reasoning as the rest.
TS_CLI_MIN=0.26.1
install_tree_sitter() {
	if have tree-sitter; then
		cur=$(tree-sitter --version 2>/dev/null | awk '{print $2}')
		# sort -V puts the smaller version first; if that is still the minimum,
		# what is installed is new enough.
		if [ -n "$cur" ] &&
			[ "$(printf '%s\n%s\n' "$TS_CLI_MIN" "$cur" | sort -V | head -1)" = "$TS_CLI_MIN" ]; then
			echo "  already present ($cur)"
			return 0
		fi
		echo "  ${cur:-unknown} is older than $TS_CLI_MIN - replacing"
	fi
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/tree-sitter.gz" \
		"https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$TS_ARCH.gz"
	gunzip -c "$tmp/tree-sitter.gz" >"$tmp/tree-sitter"
	install -m 755 "$tmp/tree-sitter" "$BIN/tree-sitter"
	rm -rf "$tmp"
}

# --------------------------------------------------------------------- eza
# Official (eza INSTALL.md): the deb.gierens.de apt repository.
install_eza() {
	if have eza; then
		echo "  already present"
		return 0
	fi
	sudo mkdir -p /etc/apt/keyrings
	wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc |
		sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
	echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" |
		sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
	sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
	sudo apt-get update -qq
	sudo apt-get install -y eza
}

# -------------------------------------------------------------------- yazi
# Official (yazi docs): the project's own apt repository for Debian/Ubuntu.
# Replaces an earlier hand-rolled release-zip fetch.
install_yazi() {
	if have yazi; then
		echo "  already present"
		return 0
	fi
	curl -fsSL https://yazi-rs.github.io/builds/yazi-keyring.gpg |
		sudo tee /usr/share/keyrings/yazi-keyring.gpg >/dev/null
	echo 'deb [signed-by=/usr/share/keyrings/yazi-keyring.gpg] https://yazi-rs.github.io/builds/ stable main' |
		sudo tee /etc/apt/sources.list.d/yazi.list >/dev/null
	sudo apt-get update -qq
	sudo apt-get install -y yazi
}

# ----------------------------------------------------------------- ghostty
# Official (ghostty.org/docs/install/binary): the Ubuntu archive from 26.04,
# and before that the community .deb, which upstream documents as the only
# prebuilt option for older Ubuntu. Same shape as lazygit below.
install_ghostty() {
	if have ghostty; then
		echo "  already present"
		return 0
	fi
	if apt-cache show ghostty >/dev/null 2>&1; then
		echo "  packaged for this release - installing from apt"
		sudo apt-get install -y ghostty
	else
		echo "  not in the archive for this release - using the community .deb"
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
	fi
}

# --------------------------------------------------------------------- fzf
# Official (fzf README): git clone + install script.
#
# --no-update-rc is essential: the script appends PATH and shell-integration
# lines to ~/.zshrc, which here is a symlink into this repo, so the install
# would write itself into the dotfiles and follow us to other machines.
# .zshrc already puts ~/.fzf/bin on PATH and calls `fzf --zsh` itself.
install_fzf() {
	if [ ! -d "$HOME/.fzf" ]; then
		git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
		"$HOME/.fzf/install" --all --no-update-rc
	else
		echo "  already present - updating"
		git -C "$HOME/.fzf" pull --ff-only --quiet || true
		"$HOME/.fzf/install" --all --no-update-rc >/dev/null
	fi
	# An earlier version of this script dropped an fzf here; ~/.local/bin precedes
	# ~/.fzf/bin on PATH, so a leftover would shadow the real install.
	if [ -f "$BIN/fzf" ] && [ ! -L "$BIN/fzf" ]; then
		rm -f "$BIN/fzf"
		echo "  removed stale $BIN/fzf"
	fi
}

# ------------------------------------------------------------------ zoxide
# Official (zoxide README): the upstream install script.
install_zoxide() {
	if have zoxide; then
		echo "  already present"
		return 0
	fi
	curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
}

# -------------------------------------------------------------- oh-my-posh
# Official (ohmyposh.dev): install script; -d selects the target directory.
install_oh_my_posh() {
	if have oh-my-posh; then
		echo "  already present"
		return 0
	fi
	curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$BIN"
}

# ----------------------------------------------------------------- lazygit
# Official (lazygit README): apt where packaged (Ubuntu 25.10+), otherwise the
# documented release recipe, including their architecture mapping.
install_lazygit() {
	if have lazygit; then
		echo "  already present"
		return 0
	fi
	if apt-cache show lazygit >/dev/null 2>&1; then
		sudo apt-get install -y lazygit
	else
		tmp=$(mktemp -d)
		# Resolve the version from the releases/latest redirect: unlike the
		# GitHub API, it is not rate-limited for anonymous callers.
		LAZYGIT_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
			"https://github.com/jesseduffield/lazygit/releases/latest" | sed 's|.*/v||')
		curl -fsSL -o "$tmp/lazygit.tar.gz" \
			"https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${GO_ARCH}.tar.gz"
		tar -xf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
		sudo install "$tmp/lazygit" -D -t /usr/local/bin/
		rm -rf "$tmp"
	fi
}

# --------------------------------------------------------------- lazydocker
# Official (lazydocker README): the upstream install script.
install_lazydocker() {
	if have lazydocker; then
		echo "  already present"
		return 0
	fi
	curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh |
		DIR="$BIN" bash
}

# -------------------------------------------------------------- git-delta
# Official (delta docs): install the .deb from the releases page.
install_delta() {
	if have delta; then
		echo "  already present"
		return 0
	fi
	tmp=$(mktemp -d)
	# Same redirect trick as lazygit: avoids GitHub API rate limits.
	DELTA_VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
		"https://github.com/dandavison/delta/releases/latest" | sed 's|.*/||')
	curl -fsSL -o "$tmp/delta.deb" \
		"https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DEB_ARCH}.deb"
	sudo dpkg -i "$tmp/delta.deb"
	rm -rf "$tmp"
}

# ---------------------------------------------------------------------- gh
# Official (cli.github.com): GitHub's apt repository.
install_gh() {
	if have gh; then
		echo "  already present"
		return 0
	fi
	sudo mkdir -p -m 755 /etc/apt/keyrings
	wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg |
		sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
	sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
		sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
	sudo apt-get update -qq
	sudo apt-get install -y gh
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

# ----------------------------------------------------------- signal desktop
# Official (signal.org/download): their apt repository. The keyring and the
# deb822 source file are checked in under bootstrap/assets so the step does
# not depend on signal.org serving the key.
install_signal() {
	if have signal-desktop; then
		echo "  already present"
		return 0
	fi
	sudo install -m 644 "$DOTFILES/bootstrap/assets/signal-desktop-keyring.gpg" /usr/share/keyrings/
	sudo install -m 644 "$DOTFILES/bootstrap/assets/signal-desktop.sources" /etc/apt/sources.list.d/
	sudo apt-get update -qq
	sudo apt-get install -y signal-desktop
}

# -------------------------------------------------------------------- font
# Required: oh-my-posh and the eza --icons aliases render as tofu without it.
install_font() {
	FONTDIR="$HOME/.local/share/fonts"
	if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
		echo "  already present"
		return 0
	fi
	mkdir -p "$FONTDIR"
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/JetBrainsMono.zip" \
		https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
	unzip -qo "$tmp/JetBrainsMono.zip" -d "$FONTDIR/JetBrainsMono"
	fc-cache -f >/dev/null
	rm -rf "$tmp"
}

# ------------------------------------------------------------------- link
# Linking is shared across OSes; install.sh owns conflict backup and stow.
link_dotfiles() {
	"$DOTFILES/install.sh"
}

# ----------------------------------------------------------- yazi packages
# Unlike zinit and TPM, yazi does not self-install its plugins: init.lua
# `require`s them outright, so a fresh machine fails to start yazi at all.
# plugins/ and flavors/ are gitignored, so this has to run after stow puts
# package.toml in place. `install` honours the pinned revs; `upgrade` would
# move them and rewrite package.toml inside the repo.
install_yazi_packages() {
	if ! have ya; then
		echo "  ya is not on PATH - the yazi step must have failed" >&2
		return 1
	fi
	ya pkg install
}

# ------------------------------------------------------------ default shell
# A step like the rest, so a chsh that hangs or an odd passwd database costs
# the summary a line instead of the run. The relogin notice has to outlive the
# step's subshell, hence the marker file rather than a variable.
RELOGIN_MARKER="$(mktemp -u)"
set_default_shell() {
	LOGIN_SHELL=$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)
	if [ "$(basename "$LOGIN_SHELL")" != "zsh" ]; then
		if chsh -s "$(command -v zsh)"; then
			: >"$RELOGIN_MARKER"
		else
			# Common on company LDAP/AD-managed accounts. Chain from bash instead:
			# terminal-agnostic, and survives switching emulators.
			echo "  chsh failed (typical on managed accounts) - falling back to a .bashrc exec"
			LINE='[ -z "$ZSH_VERSION" ] && [ -x "$(command -v zsh)" ] && exec zsh -l'
			grep -qF "$LINE" "$HOME/.bashrc" 2>/dev/null || echo "$LINE" >>"$HOME/.bashrc"
		fi
	else
		# passwd is already zsh, but $SHELL in this desktop session may still be
		# stale from an earlier login. Terminals that read $SHELL (Ghostty among
		# them) will keep launching the old shell until the session restarts.
		echo "  already zsh"
		if [ "$(basename "${SHELL:-}")" != "zsh" ]; then : >"$RELOGIN_MARKER"; fi
	fi
}

# ------------------------------------------------------------------- run
step "apt packages" install_apt
step "Neovim (official tarball -> /opt/nvim-linux-$NVIM_ARCH)" install_neovim
step "tree-sitter CLI (official release binary)" install_tree_sitter
step "eza (official apt repository)" install_eza
step "yazi (official apt repository)" install_yazi
step "Ghostty (official documented method)" install_ghostty
step "fzf (official git method)" install_fzf
step "zoxide (official install script)" install_zoxide
step "oh-my-posh (official install script)" install_oh_my_posh
step "lazygit (apt, else official release recipe)" install_lazygit
step "lazydocker (official install script)" install_lazydocker
step "git-delta (official .deb)" install_delta
step "GitHub CLI (official apt repository)" install_gh
step "nvm (official install script)" install_nvm
step "Signal Desktop (official apt repository)" install_signal
step "JetBrainsMono Nerd Font" install_font

hash -r

step "Linking dotfiles into \$HOME (stow)" link_dotfiles
step "yazi plugins and flavors (ya pkg install)" install_yazi_packages
step "Default shell" set_default_shell

# ------------------------------------------------------------------ verify
# Installing a tool and having it reachable are different things: the nvim
# tarball unpacks to a bin/ subdirectory, which is not the same as its root.
# Check against the PATH .zshrc actually builds, not this script's.
log "Verifying tools resolve on the shell PATH"
CHECK_PATH="$HOME/.local/bin:$HOME/.fzf/bin:/opt/nvim/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
missing=""
for t in nvim tree-sitter tmux zsh stow fd bat eza zoxide oh-my-posh yazi ya ghostty lazygit lazydocker delta git gh rg jq; do
	PATH="$CHECK_PATH" command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
# Presence is not enough for fzf: an old apt build resolves fine but has no --zsh.
PATH="$CHECK_PATH" fzf --zsh >/dev/null 2>&1 || missing="$missing fzf(--zsh-unsupported)"
if [ -n "$missing" ]; then
	echo "  MISSING:$missing"
	echo "  (see README troubleshooting)"
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
	log "Log out and back in before continuing."
	cat <<'EOF'
Your login shell is now zsh, but $SHELL in this desktop session is still
stale. Terminals that pick the shell from $SHELL (Ghostty does) will keep
launching the old one until you end the session. A new window is not
enough - log out and back in, or reboot.
EOF
fi

log "Then:"
cat <<'EOF'
  1. zinit auto-installs plugins on first zsh launch (wait a few seconds)
  2. Start tmux once; TPM auto-clones and installs plugins
  3. nvm install --lts
  4. Set your terminal font to "JetBrainsMono Nerd Font"
EOF

if [ "${#STEPS_FAILED[@]}" -gt 0 ]; then
	printf '\n\033[1;31m%d step(s) failed.\033[0m Re-run ./bootstrap.sh to retry them;\n' "${#STEPS_FAILED[@]}"
	echo "everything that succeeded is skipped on the second pass."
	exit 1
fi
