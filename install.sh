#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/echin-dotfiles/backups/$(date +%Y%m%d-%H%M%S)-$$"
SKIP_DEPS="${DOTFILES_SKIP_DEPENDENCIES:-0}"
SKIP_NODE="${DOTFILES_SKIP_NODE:-0}"

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --skip-deps   Skip Homebrew, plugins and language servers (Node has --skip-node).
  --skip-node   Install nvm but do not install or select Node.js LTS.
  -h, --help    Show this help.

Environment overrides:
  DOTFILES_SKIP_DEPENDENCIES=1  Same as --skip-deps.
  DOTFILES_SKIP_NODE=1          Same as --skip-node.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --skip-deps) SKIP_DEPS=1 ;;
    --skip-node) SKIP_NODE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[echin-dotfiles] %s\n' "$*"; }
warn() { printf '[echin-dotfiles] warning: %s\n' "$*" >&2; }

backup_and_link() {
  local source="$1" target="$2"
  mkdir -p "$(dirname -- "$target")"
  if [ -L "$target" ] && [ "$(readlink -- "$target")" = "$source" ]; then
    log "already linked: $target"
    return
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    mv -- "$target" "$BACKUP_DIR/$(basename -- "$target")"
    log "backed up $(basename -- "$target") to $BACKUP_DIR"
  fi
  ln -s "$source" "$target"
  log "linked $target"
}

brew_install_formula() {
  local formula="$1"
  if ! brew list --formula "$formula" >/dev/null 2>&1; then
    brew install "$formula"
  fi
}

brew_install_cask() {
  local cask="$1"
  if ! brew list --cask "$cask" >/dev/null 2>&1; then
    brew install --cask "$cask"
  fi
}

if [ "$(uname -s)" != "Darwin" ]; then
  warn "This setup targets macOS (Ghostty and Herdr are installed through Homebrew). Continuing with portable config links."
fi

if [ "$SKIP_DEPS" != 1 ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo 'Homebrew is required. Install it from https://brew.sh, or use --skip-deps to link only.' >&2
    exit 1
  else
    log "installing runtime dependencies through Homebrew"
    brew_install_formula nvm
    brew_install_formula herdr
    brew_install_formula neovim
    brew_install_formula ripgrep
    brew_install_formula fd
    brew_install_formula lazygit
    brew_install_formula tree-sitter-cli
    brew_install_formula gopls
    brew_install_formula python
    brew_install_formula zsh-autosuggestions
    brew_install_formula zsh-syntax-highlighting
    brew_install_cask ghostty
    brew_install_cask font-jetbrains-mono-nerd-font
  fi
fi

if [ ! -d "$HOME/.oh-my-zsh" ] && [ "$SKIP_DEPS" != 1 ]; then
  if command -v git >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  else
    warn "git is unavailable; cannot install Oh My Zsh."
  fi
fi

if [ -d "$HOME/.oh-my-zsh" ] && [ "$SKIP_DEPS" != 1 ]; then
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    plugin_dir="$HOME/.oh-my-zsh/custom/plugins/$plugin"
    if [ ! -d "$plugin_dir" ]; then
      git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$plugin_dir"
    fi
  done
fi

mkdir -p "$HOME/.nvm"

# Link only portable, reviewed files. Shell history, Herdr sessions, and logs
# stay local and are never copied into the repository.
backup_and_link "$REPO_DIR/config/zsh/.zprofile" "$HOME/.zprofile"
backup_and_link "$REPO_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
backup_and_link "$REPO_DIR/config/nvim" "$HOME/.config/nvim"
backup_and_link "$REPO_DIR/config/ghostty/config" "$HOME/.config/ghostty/config"
backup_and_link "$REPO_DIR/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
backup_and_link "$REPO_DIR/bin/mcode" "$HOME/.local/bin/mcode"
backup_and_link "$REPO_DIR/bin/mreview" "$HOME/.local/bin/mreview"
backup_and_link "$REPO_DIR/lib/mate-code/resolve-review-commit.py" "$HOME/.local/lib/mate-code/resolve-review-commit.py"

if [ "$SKIP_NODE" != 1 ]; then
  # Load into this process so npm below uses the selected Node version.
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # nvm is designed to be sourced without nounset; keep strict mode for our code.
  set +u
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    . "$HOME/.nvm/nvm.sh" --no-use
  elif command -v brew >/dev/null 2>&1 && [ -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]; then
    . "$(brew --prefix nvm)/nvm.sh" --no-use
  fi
  if command -v nvm >/dev/null 2>&1; then
    if ! nvm version default >/dev/null 2>&1 || [ "$(nvm version default)" = "N/A" ]; then
      log "installing Node.js LTS through nvm"
      nvm install --lts
      nvm alias default 'lts/*'
    else
      nvm use default
    fi
  else
    warn "nvm is not available yet; run 'brew install nvm' and rerun ./install.sh."
  fi
  set -u
fi

if [ "$SKIP_DEPS" != 1 ]; then
  command -v npm >/dev/null 2>&1 || { echo 'npm is required to install the Neovim language servers.' >&2; exit 1; }
  tools_dir="$HOME/.local/share/mate-code-tools"
  mkdir -p "$tools_dir"
  cp "$REPO_DIR/tools/mate-code-tools/package.json" "$REPO_DIR/tools/mate-code-tools/package-lock.json" "$tools_dir/"
  # Use the physical directory to avoid /var vs /private/var prefix differences.
  (cd -P "$tools_dir" && npm ci --ignore-scripts --no-audit --no-fund)
  command -v nvim >/dev/null 2>&1 || { echo 'Neovim is required; install it and rerun ./install.sh.' >&2; exit 1; }
  log 'restoring Neovim plugins from lazy-lock.json (requires GitHub access)'
  DOTFILES_NVIM_INSTALL=1 DOTFILES_NVIM_CHECK="$REPO_DIR/scripts/check-nvim.lua" nvim --headless '+Lazy! restore' '+lua dofile(vim.env.DOTFILES_NVIM_CHECK)' +qa
fi

log "installation complete"
log "open a new terminal, or run: exec zsh -l"
log "backups (when needed): $BACKUP_DIR"
