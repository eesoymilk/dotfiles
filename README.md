# ✨ dotfiles

One repo for every machine: macOS (air), Ubuntu, and Omarchy (Arch, btw).
Shared configs live once in `common/`; each OS adds only what is genuinely its own.

*The Omarchy machine would like you to know it still runs Arch. It just stopped hand-writing its own waybar config.* 🗿

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Omarchy](https://img.shields.io/badge/Omarchy-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)

## 🎯 Layout

Each top-level package is a [GNU stow](https://www.gnu.org/software/stow/) package mirroring `$HOME`.
Every machine gets `common` plus exactly one OS package.

```
common/     zsh core, nvim, tmux, oh-my-posh, git, gh, yazi, herdr, lazygit,
            AGENTS.md, .agents/skills (shared + curated Codex skills),
            .claude (agents, statusline), .codex (config, agents)
macos/      aerospace, ghostty, brew shellenv + mac PATH (zsh pre/post hooks)
ubuntu/     ghostty, ubuntu PATH hooks
omarchy/    ghostty overrides, wallpaper + theme-set hook, mise/BROWSER zsh hooks
bootstrap/  per-OS tool installers (ubuntu.sh, omarchy.sh, macos.sh) + assets
tests/      docker E2E tests (fresh container -> bootstrap -> verify)
```

### How per-OS differences work

- `.zshrc` is shared; it sources `~/.config/zsh/pre.zsh` (PATH, brew shellenv) first and `~/.config/zsh/post.zsh` (machine extras) near the end. Each OS package provides both.
- `ghostty`: mac and Ubuntu each ship a full config (Catppuccin Mocha). On Omarchy, `~/.config/ghostty/config` stays Omarchy's own real file, because `omarchy font set` and `omarchy display text size` rewrite it with `sed -i` and the theme switcher includes its palette from it; `install.sh` appends `config-file = ?user.conf` so the stowed `user.conf` overrides load last.
- Colours: tmux, herdr, and the oh-my-posh prompt use ANSI colours only, so they take the terminal's palette. That is the active Omarchy theme on Omarchy and Catppuccin elsewhere. nvim reads the Omarchy theme's colorscheme from `~/.local/state/omarchy/current/theme/neovim.lua` and falls back to Catppuccin.
- `tmux` and `nvim` handle the few OS differences inline (`pbcopy`/`wl-copy`, Skim/Okular).

## 🚀 Install

```sh
git clone https://github.com/eesoymilk/dotfiles.git ~/dotfiles
cd ~/dotfiles

./install.sh              # link configs only (needs stow)
./install.sh --bootstrap  # fresh machine: install all tools, then link
```

`install.sh` detects the OS, stows `common` + the OS package, and backs up any conflicting real files to `~/dotfiles-backup-<timestamp>/`.
Before replacing `~/.config/git/config` it copies any `user.name`/`user.email` found there into `~/.gitconfig`, so the identity Omarchy's installer wrote survives.
It then links `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` -> `~/AGENTS.md`, and the shared `brainstorm` and `big-task` skills into `~/.claude/skills/`.
Safe to re-run; credentials, session history, and caches under `~/.claude` and `~/.codex` are never touched.

Bootstrap installs every tool by its officially documented method (Claude Code and Codex via their standalone installers) and never lets one failed step abort the rest; the summary at the end names anything that failed and re-running retries only that.

### Per-OS notes

- **Ubuntu**: apt where the archive is fresh enough, official repos/scripts elsewhere. Also installs Signal Desktop, the JetBrainsMono Nerd Font, and the packaged Bubblewrap AppArmor profile required by the Codex sandbox on Ubuntu 24.04.
- **Omarchy**: Omarchy owns the desktop (Hyprland, bar, launcher, lock, idle, notifications, screenshots, voxtype dictation) and ships most of the CLI set, so the bootstrap only fills gaps through Omarchy's own installers: `omarchy pkg add zsh stow yazi git-delta`, `omarchy install terminal ghostty`, and mise for claude/codex/gh (node too). oh-my-posh and oxker use their official install scripts (AUR-only otherwise). Plain Arch without Omarchy is no longer supported; the old hand-rolled Hyprland/waybar/wofi/wlogout setup lives in git history. I did my rite of passage. Now I just want the computer to work.
- **macOS**: Homebrew for everything, casks for ghostty, aerospace, and the nerd font.

## 🤖 Agents

Claude Code and Codex share one instruction file and one skills directory; each client keeps its own specialist agents and UI settings.

|                   | Claude Code                                                     | Codex                                                       |
|-------------------|-----------------------------------------------------------------|-------------------------------------------------------------|
| Instructions      | `~/.claude/CLAUDE.md` -> `~/AGENTS.md`                          | `~/.codex/AGENTS.md` -> `~/AGENTS.md`                       |
| Skills            | `~/.claude/skills/{brainstorm,big-task}` -> `~/.agents/skills/` | `~/.agents/skills/`                                         |
| Specialist agents | `~/.claude/agents/*.md`                                         | `~/.codex/agents/*.toml`                                    |
| Permissions       | auto mode                                                       | on-request approvals + Auto-review, workspace-write sandbox |
| Footer            | `~/.claude/statusline.sh`                                       | native footer                                               |
| Herdr pane        | `prefix+alt+c`                                                  | `prefix+alt+x`                                              |

- **Skills**: `common/.agents/skills` is the canonical home. `brainstorm` and `big-task` are hand-written and shared; Claude Code reaches them through the links `install.sh` creates. `gh-address-comments`, `gh-fix-ci`, `playwright`, `security-best-practices`, and `security-threat-model` are vendored from [openai/skills](https://github.com/openai/skills) for Codex, so a fresh bootstrap needs no second install step.
- **Specialist agents**: the same five roles on both sides - Python, TypeScript, debugger, code reviewer, and Git workflow. Claude Code reads Markdown under `.claude/agents`; Codex reads TOML under `.codex/agents`.
- **Auto-review**: `~/.codex/config.toml` sets `approval_policy = "on-request"`, `approvals_reviewer = "auto_review"`, and `sandbox_mode = "workspace-write"`, the Codex equivalent of Claude Code auto mode. It keeps `gpt-5.6-sol` at `medium` reasoning. Herdr launches plain `codex` so this file stays in charge of permissions.
- **Footer**: Claude Code renders `statusline.sh`. Codex uses its native TUI footer showing model and reasoning, remaining context, Git branch, and current directory, in that order; it does not reuse the Claude script or layout.

## 🧪 Tests

Fresh-container E2E: build runs the real `./install.sh --bootstrap`, then `tests/verify.sh` hard-asserts symlinks, tools on PATH, and that interactive zsh boots.

```sh
./tests/run.sh          # ubuntu (docker required, takes a while)
```

macOS and Omarchy cannot run in docker; run `tests/verify.sh` on those machines after installing.
(The Omarchy machine has probably shipped a kernel update since you started reading this sentence.)

## 🕰️ History

This repo unifies the former `ubuntu-dotfiles`, `air-dotfiles`, and `arch-dotfiles-btw` repos, which had drifted apart.
Ubuntu was the merge base (newest fixes); the mac and arch trees contributed their OS-specific parts.
