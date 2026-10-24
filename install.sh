#!/usr/bin/env bash
# Link this dotfiles repo into $HOME with GNU stow.
#
# Every machine gets the `common` package plus its own OS package
# (macos, ubuntu, or omarchy). Safe to re-run: existing correct links are
# left alone and conflicting real files are backed up first.
#
# Usage:
#   ./install.sh              link configs only (stow must be installed)
#   ./install.sh --bootstrap  install tools via bootstrap/<os>.sh, then link
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------ detect OS
detect_os() {
	case "$(uname -s)" in
	Darwin)
		echo macos
		return
		;;
	Linux)
		if [ -r /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "${ID:-} ${ID_LIKE:-}" in
			*arch*)
				# Only Omarchy is supported on the Arch side: it owns the desktop
				# (Hyprland, bar, launcher, lock), so there is no plain-Arch package.
				if command -v omarchy >/dev/null 2>&1; then
					echo omarchy && return
				fi
				echo "Arch without Omarchy is no longer supported (see README)." >&2
				exit 1
				;;
			*ubuntu* | *debian*) echo ubuntu && return ;;
			esac
		fi
		;;
	esac
	echo "Unsupported OS: $(uname -s) (${ID:-unknown})" >&2
	exit 1
}

OS_PKG="$(detect_os)"
echo "Detected OS package: $OS_PKG"

# ------------------------------------------------------------------ bootstrap
if [ "${1:-}" = "--bootstrap" ]; then
	# The bootstrap script installs tools and calls back into this script
	# (without the flag) as its linking step.
	exec bash "$DOTFILES/bootstrap/$OS_PKG.sh"
fi

# ---------------------------------------------------------------------- stow
if ! command -v stow >/dev/null 2>&1; then
	echo "GNU stow is required. Install it (or run ./install.sh --bootstrap)." >&2
	exit 1
fi

# Pre-create these so stow links their *contents* instead of folding the whole
# directory into a single symlink. Without this, an app writing to ~/.config
# would be writing straight into the repo. ~/.codex is where Codex keeps
# auth.json and its sqlite state, and ~/.agents/skills and ~/.claude/skills
# hold machine-local skills next to the repo-provided ones.
BACKUP="$HOME/dotfiles-backup-$(date +%Y%m%d%H%M%S)"
for dir in .claude/skills .agents/skills .codex/agents; do
	# Older installs folded ~/.claude/skills into a repo symlink. Move any
	# folded directory aside before creating the real runtime directory.
	if [ -L "$HOME/$dir" ]; then
		mkdir -p "$BACKUP/$(dirname "$dir")"
		mv "$HOME/$dir" "$BACKUP/$dir"
		echo "  moved legacy directory link $dir"
	fi
done
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.claude/skills" \
	"$HOME/.agents/skills" "$HOME/.codex/agents"
# Omarchy writes into both of these itself (its own ghostty config, sample
# hooks), so only individual files may be links.
if [ "$OS_PKG" = "omarchy" ]; then
	mkdir -p "$HOME/.config/ghostty" "$HOME/.config/omarchy/hooks/theme-set.d"

	# Omarchy seeds ~/.config/nvim with a LazyVim starter. The per-file
	# conflict backup below would leave its extra plugin specs behind for this
	# config's `import = "plugins"` to load, so move the whole tree aside.
	if [ -f "$HOME/.config/nvim/lazyvim.json" ] && [ ! -L "$HOME/.config/nvim" ]; then
		mkdir -p "$BACKUP/.config"
		mv "$HOME/.config/nvim" "$BACKUP/.config/nvim"
		echo "  moved Omarchy's LazyVim config aside"
	fi
fi

# The stowed git config replaces ~/.config/git/config, which is where Omarchy's
# installer (and `git config --global` without a ~/.gitconfig) put the user's
# identity. Carry it over to ~/.gitconfig, which git reads as well, so commits
# keep their author. --file, because --global would write into the repo.
if [ -f "$HOME/.config/git/config" ] && [ ! -L "$HOME/.config/git/config" ]; then
	for key in user.name user.email user.signingkey; do
		val=$(git config --file "$HOME/.config/git/config" --get "$key" || true)
		if [ -n "$val" ] && ! git config --file "$HOME/.gitconfig" --get "$key" >/dev/null 2>&1; then
			git config --file "$HOME/.gitconfig" "$key" "$val"
			echo "  kept $key in ~/.gitconfig"
		fi
	done
fi

# Move conflicting real files aside rather than using `stow --adopt`, which
# would pull the OS's defaults *into* the repo and overwrite these configs.
# stow's conflict wording differs by version, so match both:
#   2.3.x: "existing target is neither a link nor a directory: PATH"
#   2.4.x: "cannot stow SRC over existing target PATH since ..."
conflicts=$(stow -d "$DOTFILES" -t "$HOME" -n common "$OS_PKG" 2>&1 | sed -n \
	-e 's/.*existing target is neither a link nor a directory: *\(.*\)$/\1/p' \
	-e 's/.*cannot stow .* over existing target \(.*\) since .*/\1/p' |
	sed 's/[[:space:]]*$//' | sort -u || true)
if [ -n "$conflicts" ]; then
	echo "Backing up conflicting files to $BACKUP"
	while IFS= read -r rel; do
		[ -z "$rel" ] && continue
		mkdir -p "$BACKUP/$(dirname "$rel")"
		mv "$HOME/$rel" "$BACKUP/$rel"
		echo "  moved $rel"
	done <<<"$conflicts"
fi

stow -d "$DOTFILES" -t "$HOME" common "$OS_PKG"
chmod +x "$HOME/.local/bin/tmux-sessionizer" 2>/dev/null || true

# Omarchy: ~/.config/ghostty/config is Omarchy's own file (see the header of
# omarchy/.config/ghostty/user.conf). Seed it if missing and make it include
# the stowed overrides. `omarchy refresh ghostty` drops the line; re-run this.
if [ "$OS_PKG" = "omarchy" ]; then
	GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
	if [ ! -e "$GHOSTTY_CONFIG" ]; then
		cp "${OMARCHY_PATH:-/usr/share/omarchy}/config/ghostty/config" "$GHOSTTY_CONFIG"
	fi
	INCLUDE='config-file = ?user.conf'
	if ! grep -qxF "$INCLUDE" "$GHOSTTY_CONFIG"; then
		printf '\n# Personal overrides, stowed from the dotfiles repo.\n%s\n' "$INCLUDE" >>"$GHOSTTY_CONFIG"
	fi
fi

# Claude Code reads ~/.claude/CLAUDE.md and Codex reads ~/.codex/AGENTS.md;
# ~/AGENTS.md is the single source for both.
ln -sf "$HOME/AGENTS.md" "$HOME/.claude/CLAUDE.md"
ln -sf "$HOME/AGENTS.md" "$HOME/.codex/AGENTS.md"

# Claude Code loads skills from ~/.claude/skills; the shared ones live in
# ~/.agents/skills so Codex sees the same files. Only these are shared:
# the curated skills stowed alongside them are Codex-only.
for skill in brainstorm big-task wt-open wt-cleanup; do
	ln -sfn "../../.agents/skills/$skill" "$HOME/.claude/skills/$skill"
done

echo "Linked common + $OS_PKG into $HOME. Restart your shell to pick up .zshrc."
