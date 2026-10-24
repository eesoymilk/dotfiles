# Omarchy: mise owns the language runtimes and the agent CLIs (node, gh,
# claude, codex). Omarchy only activates it for bash, so do it for zsh here.
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
