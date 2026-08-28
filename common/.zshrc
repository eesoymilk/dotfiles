# Machine-specific setup that must run first (PATH additions, brew shellenv).
# Provided by this machine's stow package (macos/ubuntu/arch).
[ -f "$HOME/.config/zsh/pre.zsh" ] && source "$HOME/.config/zsh/pre.zsh"

# Path
export PATH="$HOME/.local/bin:$PATH"

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::command-not-found

# Docker CLI completions (fpath must be set before compinit)
[ -d "$HOME/.docker/completions" ] && fpath=("$HOME/.docker/completions" $fpath)

# Load completions
autoload -Uz compinit && compinit

zinit cdreplay -q

# Load oh-my-posh (skip Apple Terminal, which can't render it)
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/zen.toml)"
fi

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --color=always --icons=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --color=always --icons=always $realpath'

# Exports
export EDITOR=nvim

# Aliases
alias ls='eza --color=always --icons=always'
alias ll='eza -l --color=always --icons=always'
alias la='eza -a --color=always --icons=always'
alias lla='eza -la --color=always --icons=always'
alias lt='eza --tree --color=always --icons=always'
alias lgi='eza -la --color=always --icons=always --git-ignore'
alias ltgi='eza --tree --color=always --icons=always --git-ignore'
alias cat='bat'
alias lg='lazygit'
alias lzd='lazydocker'
alias vim='nvim'
alias c='clear'
alias gs='git status'
alias gl='git log --decorate --oneline --graph'
alias ga='git add'
alias gac='git commit -am'
alias gc='git commit'
alias gp='git push'
alias tms='tmux-sessionizer'

# Shell integrations
eval "$(fzf --zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm (per-OS home, same convention pnpm's own installer uses)
case "$(uname -s)" in
  Darwin) export PNPM_HOME="$HOME/Library/pnpm" ;;
  *)      export PNPM_HOME="$HOME/.local/share/pnpm" ;;
esac
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Yazi shell wrapper
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}


# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# Machine-specific extras (micromamba, ydotool, linuxbrew, ...).
# Provided by this machine's stow package; runs before zoxide so init order holds.
[ -f "$HOME/.config/zsh/post.zsh" ] && source "$HOME/.config/zsh/post.zsh"

# zoxide must be initialized last (its doctor warns otherwise).
# Claude Code's shell snapshot re-creates functions after init, so
# the doctor check false-positives there; disable it in those sessions.
[ -n "$CLAUDECODE" ] && export _ZO_DOCTOR=0
eval "$(zoxide init --cmd cd zsh)"

# Machine-local config (not committed) - work/company settings live in ~/.zshrc.local
# `if` rather than `&&`: a bare && chain leaves $? = 1 when the file is absent,
# which oh-my-posh renders as a red first prompt in every new pane.
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
