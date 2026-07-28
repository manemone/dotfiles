# =============================================================================
# Resolve dotfiles directory (follows symlinks from ~/.zshrc)
# =============================================================================
# Use %x prompt expansion to get the sourced file path.
# This works regardless of FUNCTION_ARGZERO / POSIX_ARGZERO settings,
# unlike $0 which depends on those options.
_ZSHRC_PATH="${${(%):-%x}:A}"
DOTFILES_DIR="${_ZSHRC_PATH:h:h}"
unset _ZSHRC_PATH

# =============================================================================
# Source shared helpers (CURRENT_PLATFORM, is_wsl, ensure_command)
# =============================================================================
if [ -f "$DOTFILES_DIR/shared/helpers.sh" ]; then
  source "$DOTFILES_DIR/shared/helpers.sh"
fi

# Fallback WSL detection if helpers.sh is unavailable
# (minimum fallback — keep in sync with shared/helpers.sh)
if ! command -v is_wsl >/dev/null 2>&1; then
  is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
  }
fi

# =============================================================================
# Antidote Plugin Manager
# =============================================================================
ANTIDOTE_HOME="${ANTIDOTE_HOME:-$HOME/.antidote}"
if [ -f "$ANTIDOTE_HOME/antidote.zsh" ] && [ -f "$HOME/.zsh_plugins.txt" ]; then
  source "$ANTIDOTE_HOME/antidote.zsh"
  antidote load "$HOME/.zsh_plugins.txt"
else
  print -ru2 -- "zshrc: Antidote not set up. Run <dotfiles>/zsh/deploy.sh"
fi

# Initialize completion system (zplug used to do this; antidote doesn't)
autoload -Uz compinit && compinit

# =============================================================================
# History
# =============================================================================
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_VERIFY

# =============================================================================
# Aliases
# =============================================================================
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias be="bundle exec"
alias bx="bundle exec"

# NeoVim (only if installed)
if command -v nvim >/dev/null 2>&1; then
  alias vim="nvim"
  alias vi="nvim"
  export EDITOR=nvim
fi

# one-liner httpd
alias webrick="ruby -rwebrick -e 'WEBrick::HTTPServer.new(:DocumentRoot => \"./\", :Port => 8000).start'"

# =============================================================================
# Platform-specific Homebrew PATH
# =============================================================================
case "$CURRENT_PLATFORM" in
  Mac)
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
if [ -d "$HOME/.rbenv/bin" ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
fi
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init -)"
fi

# =============================================================================
# pyenv (Python) - skip if not installed
# =============================================================================
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
if [ -d "$PYENV_ROOT/bin" ]; then
  export PATH="$PYENV_ROOT/bin:$PATH"
fi
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
  # Check for pyenv-virtualenv via directory, not subprocess
  if [ -d "$PYENV_ROOT/plugins/pyenv-virtualenv" ]; then
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
# PostgreSQL (macOS only — WSL and Linux skip)
# =============================================================================
if [ "$CURRENT_PLATFORM" = "Mac" ] && [ -d /usr/local/var/postgres ]; then
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
# Search candidates: brew cask symlink, brew cask realpath, manual installs.
# brew --prefix (no formula name) is called once for performance.
_gcloud_candidates=()
if command -v brew >/dev/null 2>&1; then
  _brew_prefix="$(brew --prefix)"
  _gcloud_candidates+=(
    "$_brew_prefix/share/google-cloud-sdk"
    "$_brew_prefix/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
  )
fi
_gcloud_candidates+=(
  /usr/local/share/google-cloud-sdk
  "$HOME/google-cloud-sdk"
)

for _dir in $_gcloud_candidates; do
  if [ -f "$_dir/path.zsh.inc" ]; then
    source "$_dir/path.zsh.inc"
    [ -f "$_dir/completion.zsh.inc" ] && source "$_dir/completion.zsh.inc"
    break
  fi
done
unset _gcloud_candidates _brew_prefix _dir

# =============================================================================
# mise version manager (if installed)
# =============================================================================
# mise activates last so its shims take precedence for Python/Ruby/Node.
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
