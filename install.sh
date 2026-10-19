#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/echin-dotfiles/backups/$(date +%Y%m%d-%H%M%S)"
SKIP_DEPS="${DOTFILES_SKIP_DEPENDENCIES:-0}"
SKIP_NODE="${DOTFILES_SKIP_NODE:-0}"

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --skip-deps   Do not install Homebrew packages/apps or Oh My Zsh plugins.
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
    warn "Homebrew is not installed; skipping dependency installation. Install Homebrew, then rerun ./install.sh."
  else
    log "installing runtime dependencies through Homebrew"
    brew_install_formula nvm
    brew_install_formula herdr
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
backup_and_link "$REPO_DIR/config/ghostty/config" "$HOME/.config/ghostty/config"
backup_and_link "$REPO_DIR/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"

if [ "$SKIP_NODE" != 1 ]; then
  # Use a clean zsh process so this works in both interactive and CI shells.
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    . "$HOME/.nvm/nvm.sh"
  elif command -v brew >/dev/null 2>&1 && [ -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]; then
    . "$(brew --prefix nvm)/nvm.sh"
  fi
  if command -v nvm >/dev/null 2>&1; then
    if ! nvm version default >/dev/null 2>&1 || [ "$(nvm version default)" = "N/A" ]; then
      log "installing Node.js LTS through nvm"
      nvm install --lts
      nvm alias default 'lts/*'
    fi
  else
    warn "nvm is not available yet; run 'brew install nvm' and rerun ./install.sh."
  fi
fi

log "installation complete"
log "open a new terminal, or run: exec zsh -l"
log "backups (when needed): $BACKUP_DIR"
