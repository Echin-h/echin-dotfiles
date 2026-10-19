#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
failures=0
warnings=0
ok() { printf 'ok   %s\n' "$*"; }
warn() { printf 'warn %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'fail %s\n' "$*"; failures=$((failures + 1)); }

check_link() {
  local target="$1" expected="$2"
  if [ -L "$target" ] && [ "$(readlink -- "$target")" = "$expected" ]; then ok "$target -> repository"; else fail "$target is not linked to $expected"; fi
}

check_link "$HOME/.zprofile" "$REPO_DIR/config/zsh/.zprofile"
check_link "$HOME/.zshrc" "$REPO_DIR/config/zsh/.zshrc"
check_link "$HOME/.config/ghostty/config" "$REPO_DIR/config/ghostty/config"
check_link "$HOME/.config/herdr/config.toml" "$REPO_DIR/config/herdr/config.toml"

if zsh -n "$HOME/.zprofile" && zsh -n "$HOME/.zshrc"; then ok 'zsh syntax'; else fail 'zsh syntax'; fi

if zsh -lic 'command -v nvm >/dev/null 2>&1' >/dev/null 2>&1; then
  ok "nvm $(zsh -lic 'nvm --version' 2>/dev/null | tail -n 1)"
else
  warn 'nvm is not loaded in a login shell'
fi
if zsh -lic 'command -v node >/dev/null 2>&1' >/dev/null 2>&1; then
  ok "node $(zsh -lic 'node --version' 2>/dev/null | tail -n 1)"
else
  warn 'node is not installed'
fi
if [ -d '/Applications/Ghostty.app' ] || (command -v brew >/dev/null 2>&1 && brew list --cask ghostty >/dev/null 2>&1); then
  ok 'Ghostty app'
else
  warn 'Ghostty app not found'
fi
if command -v herdr >/dev/null 2>&1; then ok "Herdr $(herdr --version 2>/dev/null || true)"; else warn 'Herdr executable not found'; fi

if [ "$failures" -gt 0 ]; then
  printf '\n%d required check(s) failed; rerun ./install.sh.\n' "$failures" >&2
  exit 1
fi
printf '\nChecks passed (%d warning(s)).\n' "$warnings"
