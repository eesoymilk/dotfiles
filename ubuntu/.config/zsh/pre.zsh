# Ubuntu: fzf lives in ~/.fzf (official git install), nvim under /opt/nvim/bin
# (stable symlink bootstrap/ubuntu.sh maintains), go under /usr/local/go and
# `go install` output in ~/go/bin.
export PATH="$HOME/.fzf/bin:/opt/nvim/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
