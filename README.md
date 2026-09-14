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
            AGENTS.md, .agents/skills (shared + curated Codex skills),
            .claude (agents, statusline), .codex (config, agents)
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

`install.sh` detects the OS, stows `common` + the OS package, and backs up any conflicting real files to `~/dotfiles-backup-<timestamp>/`.
It then links `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` -> `~/AGENTS.md`, and the shared `brainstorm` and `big-task` skills into `~/.claude/skills/`.
Safe to re-run; credentials, session history, and caches under `~/.claude` and `~/.codex` are never touched.

Bootstrap installs every tool by its officially documented method (Claude Code and Codex via their standalone installers) and never lets one failed step abort the rest; the summary at the end names anything that failed and re-running retries only that.

### Per-OS notes

- **Ubuntu**: apt where the archive is fresh enough, official repos/scripts elsewhere. Also installs Signal Desktop, the JetBrainsMono Nerd Font, and the packaged Bubblewrap AppArmor profile required by the Codex sandbox on Ubuntu 24.04.
- **Arch**: pacman for nearly everything; oh-my-posh and oxker use their official install scripts (AUR-only otherwise); wlogout needs an AUR helper. `SKIP_DESKTOP=1` skips the Hyprland stack. Yes, a bootstrap script for Arch - the wiki is a great read, but I have already done my rite of passage.
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
./tests/run.sh          # ubuntu + arch (docker required, takes a while)
./tests/run.sh ubuntu   # just one
```

The Arch test is the fastest of the two, which the Arch machine also mentions unprompted.
(It is also the only container that has probably shipped a kernel update since you started reading this sentence.)

macOS cannot run in docker; run `tests/verify.sh` on the mac itself after installing.

## 🕰️ History

This repo unifies the former `ubuntu-dotfiles`, `air-dotfiles`, and `arch-dotfiles-btw` repos, which had drifted apart.
Ubuntu was the merge base (newest fixes); the mac and arch trees contributed their OS-specific parts.
