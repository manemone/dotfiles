# =============================================================================
# Resolve dotfiles directory (follows symlinks from ~/.zshrc)
# =============================================================================
_ZSHCONFIG_DIR="${0:A:h}"
DOTFILES_DIR="${_ZSHCONFIG_DIR:h}"

# =============================================================================
# Source shared helpers (is_wsl, CURRENT_PLATFORM, ensure_command)
# =============================================================================
if [ -f "$DOTFILES_DIR/shared/helpers.sh" ]; then
  source "$DOTFILES_DIR/shared/helpers.sh"
fi

# Fallback WSL detection if helpers.sh is unavailable
if ! command -v is_wsl >/dev/null 2>&1; then
  is_wsl() {
    [ -n "${WSL_DISTRO_NAME}" ] || grep -qi microsoft /proc/version 2>/dev/null
  }
fi

# =============================================================================
# Antidote Plugin Manager
# =============================================================================
ANTIDOTE_HOME="${ANTIDOTE_HOME:-$HOME/.antidote}"
if [ -f "$ANTIDOTE_HOME/antidote.zsh" ]; then
  source "$ANTIDOTE_HOME/antidote.zsh"
  antidote load "$HOME/.zsh_plugins.txt"
fi

# =============================================================================
# History
# =============================================================================
HISTSIZE=1000
HISTFILESIZE=2000

# =============================================================================
# Aliases
# =============================================================================
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias be="bundle exec"
alias bx="bundle exec"

# NeoVim
alias vim="nvim"
alias vi="nvim"
export EDITOR=nvim

# one-liner httpd
alias webrick="ruby -rwebrick -e 'WEBrick::HTTPServer.new(:DocumentRoot => \"./\", :Port => 8000).start'"

# =============================================================================
# Platform-specific Homebrew PATH
# =============================================================================
case "$(uname -s)" in
  Darwin)
    if [ -d /opt/homebrew/bin ]; then
      # Apple Silicon
      export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      # Intel Mac
      export PATH="/usr/local/bin:$PATH"
    fi
    ;;
  Linux)
    if [ -d /home/linuxbrew/.linuxbrew/bin ]; then
      export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
      export PATH="/usr/local/bin:$PATH"
    fi
    ;;
esac

# =============================================================================
# rbenv (Ruby) - skip if not installed
# =============================================================================
if command -v rbenv >/dev/null 2>&1; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
fi

# =============================================================================
# pyenv (Python) - skip if not installed
# =============================================================================
if command -v pyenv >/dev/null 2>&1; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
  if pyenv commands 2>/dev/null | grep -q virtualenv-init; then
    eval "$(pyenv virtualenv-init -)"
  fi
fi

# =============================================================================
# n (Node.js version manager) - skip if not installed
# =============================================================================
if [ -d "$HOME/.n" ]; then
  export N_PREFIX="$HOME/.n"
  export PATH="$PATH:$N_PREFIX/bin"
fi

# =============================================================================
# PostgreSQL (macOS only — skip on WSL/Linux)
# =============================================================================
if ! is_wsl && [ "$(uname -s)" = "Darwin" ] && [ -d /usr/local/var/postgres ]; then
  export PGDATA=/usr/local/var/postgres
fi

# =============================================================================
# Rust
# =============================================================================
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# =============================================================================
# Google Cloud SDK
# =============================================================================
# Try Homebrew-installed SDK first, then fall back to manual installation paths
_gcloud_sdk_path=""
if command -v brew >/dev/null 2>&1; then
  _gcloud_sdk_path="$(brew --prefix google-cloud-sdk 2>/dev/null)"
fi

if [ -n "$_gcloud_sdk_path" ] && [ -f "$_gcloud_sdk_path/path.zsh.inc" ]; then
  source "$_gcloud_sdk_path/path.zsh.inc"
elif [ -f /usr/local/share/google-cloud-sdk/path.zsh.inc ]; then
  source /usr/local/share/google-cloud-sdk/path.zsh.inc
elif [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then
  source "$HOME/google-cloud-sdk/path.zsh.inc"
fi

if [ -n "$_gcloud_sdk_path" ] && [ -f "$_gcloud_sdk_path/completion.zsh.inc" ]; then
  source "$_gcloud_sdk_path/completion.zsh.inc"
elif [ -f /usr/local/share/google-cloud-sdk/completion.zsh.inc ]; then
  source /usr/local/share/google-cloud-sdk/completion.zsh.inc
elif [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then
  source "$HOME/google-cloud-sdk/completion.zsh.inc"
fi

unset _gcloud_sdk_path
