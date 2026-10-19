# echin-dotfiles: portable interactive zsh configuration
# This file intentionally contains no credentials or host-specific paths.

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
export GOPATH="${GOPATH:-$HOME/go}"
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

# Load Homebrew's nvm when available. The installer creates ~/.nvm so upgrades
# do not remove Node versions installed through nvm.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
elif command -v brew >/dev/null 2>&1 && [ -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]; then
  . "$(brew --prefix nvm)/nvm.sh"
fi
if [ -s "$NVM_DIR/bash_completion" ]; then
  . "$NVM_DIR/bash_completion"
elif command -v brew >/dev/null 2>&1 && [ -s "$(brew --prefix nvm 2>/dev/null)/etc/bash_completion.d/nvm" ]; then
  . "$(brew --prefix nvm)/etc/bash_completion.d/nvm"
fi

# Oh My Zsh is optional at runtime: a plain zsh still starts if installation
# was interrupted before the framework was installed.
if [ -r "$ZSH/oh-my-zsh.sh" ]; then
  ZSH_THEME="robbyrussell"
  plugins=(git extract z)
  [ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && plugins+=(zsh-autosuggestions)
  [ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && plugins+=(zsh-syntax-highlighting)
  source "$ZSH/oh-my-zsh.sh"
fi

# Keep existing local tools usable without requiring them on every machine.
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
[ -d "$HOME/Library/pnpm" ] && export PNPM_HOME="$HOME/Library/pnpm"
[ -n "${PNPM_HOME:-}" ] && case ":$PATH:" in *":$PNPM_HOME:"*) ;; *) export PATH="$PNPM_HOME:$PATH" ;; esac
[ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ] && export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
[ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ] && export PATH="$HOME/Library/Application Support/JetBrains/Toolbox/scripts:$PATH"

# Small convenience command from the original setup. It remains a no-op when
# WPS Office is not installed.
wps() {
  local wps_app="/Applications/wpsoffice.app"
  if [ ! -e "$wps_app" ]; then
    print -u2 "wps: /Applications/wpsoffice.app is not installed"
    return 1
  fi
  if [ "$#" -gt 0 ]; then
    open -a "$wps_app" "$@"
  else
    open "$wps_app"
  fi
}
