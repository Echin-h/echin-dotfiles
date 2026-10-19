# Portable login-shell setup for echin-dotfiles.
# Keep machine-specific secrets and credentials outside this repository.

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi

# Homebrew and user-installed command line tools.
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
