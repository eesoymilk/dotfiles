# ✨ dotfiles

One repo for every machine: macOS (air), Ubuntu, and Arch (btw).
Shared configs live once in `common/`; each OS adds only what is genuinely its own.

*The Arch machine would like you to know it runs Arch. It mentions this before the prompt even loads.* 🗿

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Arch](https://img.shields.io/badge/Arch-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)

## 🎯 Layout

Each top-level package is a [GNU stow](https://www.gnu.org/software/stow/) package mirroring `$HOME`.
Every machine gets `common` plus exactly one OS package.

```
common/     zsh core, nvim, tmux, ghostty, oh-my-posh, git, gh, yazi, herdr,
            AGENTS.md, .claude (agents, skills, statusline)
macos/      aerospace, brew shellenv + mac PATH (zsh pre/post hooks)
ubuntu/     ubuntu PATH hooks
arch/       hyprland, waybar (mechabar submodule), wofi, wlogout, waystt,
            wallpapers, arch PATH hooks (I use this package, btw)
bootstrap/  per-OS tool installers (ubuntu.sh, arch.sh, macos.sh) + assets
tests/      docker E2E tests (fresh container -> bootstrap -> verify)
```

### How per-OS differences work

- `.zshrc` is shared; it sources `~/.config/zsh/pre.zsh` (PATH, brew shellenv) first and `~/.config/zsh/post.zsh` (machine extras) near the end. Each OS package provides both.
- `ghostty` shares one config; it ends with `config-file = ?os.conf`, and an OS package may provide `os.conf` overrides (arch does, for hyprland blur).
- `tmux` and `nvim` handle the few OS differences inline (`pbcopy`/`wl-copy`, Skim/Okular).

## 🚀 Install

```sh
git clone https://github.com/eesoymilk/dotfiles.git ~/dotfiles
cd ~/dotfiles

./install.sh              # link configs only (needs stow)
./install.sh --bootstrap  # fresh machine: install all tools, then link
```

`install.sh` detects the OS, stows `common` + the OS package, backs up any conflicting real files to `~/dotfiles-backup-<timestamp>/`, and links `~/.claude/CLAUDE.md` -> `~/AGENTS.md`.
Safe to re-run.

Bootstrap installs every tool by its officially documented method and never lets one failed step abort the rest; the summary at the end names anything that failed and re-running retries only that.

### Per-OS notes

- **Ubuntu**: apt where the archive is fresh enough, official repos/scripts elsewhere. Also installs Signal Desktop and the JetBrainsMono Nerd Font.
- **Arch**: pacman for nearly everything; oh-my-posh and lazydocker use their official install scripts (AUR-only otherwise); wlogout needs an AUR helper. `SKIP_DESKTOP=1` skips the Hyprland stack. Yes, a bootstrap script for Arch - the wiki is a great read, but I have already done my rite of passage.
- **macOS**: Homebrew for everything, casks for ghostty, aerospace, and the nerd font.

## 🧪 Tests

Fresh-container E2E: build runs the real `./install.sh --bootstrap`, then `tests/verify.sh` hard-asserts symlinks, tools on PATH, and that interactive zsh boots.

```sh
./tests/run.sh          # ubuntu + arch (docker required, takes a while)
./tests/run.sh ubuntu   # just one
```

The Arch test is the fastest of the two, which the Arch machine also mentions unprompted.
(It is also the only container that has probably shipped a kernel update since you started reading this sentence.)

macOS cannot run in docker; run `tests/verify.sh` on the mac itself after installing.

## 🕰️ History

This repo unifies the former `ubuntu-dotfiles`, `air-dotfiles`, and `arch-dotfiles-btw` repos, which had drifted apart.
Ubuntu was the merge base (newest fixes); the mac and arch trees contributed their OS-specific parts.
