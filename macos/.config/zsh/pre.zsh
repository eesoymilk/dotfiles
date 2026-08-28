# macOS: homebrew provides most tools; brew shellenv must run before anything
# that expects those tools on PATH.
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/nvim:/usr/local/go/bin:$PATH"
