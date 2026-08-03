# =============================================================================
# Resolve dotfiles directory (follows symlinks from ~/.zshrc)
# =============================================================================
# Use %x prompt expansion to get the sourced file path.
# This works regardless of FUNCTION_ARGZERO / POSIX_ARGZERO settings,
# unlike $0 which depends on those options.
#
# ~/.zshrc -> .../dotfiles/current/zsh/.zshrc, where `current` is itself a
# symlink to a dated generation directory that gets garbage-collected once
# older than DOTFILES_KEEP_GENERATIONS deploys ago. `:A` (full realpath)
# would resolve straight through `current` to that generation directory, so
# DOTFILES_DIR would end up pointing at a path that can vanish out from
# under an already-running shell after a later re-deploy's GC. Resolve only
# the ~/.zshrc symlink itself (one hop, via readlink) so DOTFILES_DIR stops
# at the stable `current` path instead.
_ZSHRC_SOURCE="${(%):-%x}"
if [ -L "$_ZSHRC_SOURCE" ]; then
  # readlink returns the link's raw target text, which is relative when the
  # symlink itself is relative (deploy.sh always writes absolute targets,
  # but a hand-made or third-party-tool link might not). Anchor a relative
  # target to the symlink's own directory so DOTFILES_DIR is always absolute.
  _ZSHRC_TARGET="$(readlink "$_ZSHRC_SOURCE")"
  case "$_ZSHRC_TARGET" in
    /*) _ZSHRC_PATH="$_ZSHRC_TARGET" ;;
    *) _ZSHRC_PATH="${_ZSHRC_SOURCE:h}/$_ZSHRC_TARGET" ;;
  esac
else
  _ZSHRC_PATH="${_ZSHRC_SOURCE:A}"
fi
DOTFILES_DIR="${_ZSHRC_PATH:h:h}"
unset _ZSHRC_SOURCE _ZSHRC_TARGET _ZSHRC_PATH

# =============================================================================
# Source shared helpers (CURRENT_PLATFORM, is_macos, is_linux, is_wsl, etc.)
# =============================================================================
if [ -f "$DOTFILES_DIR/shared/helpers.sh" ]; then
  source "$DOTFILES_DIR/shared/helpers.sh"
fi

# Fallback platform detection and helpers if shared/helpers.sh is unavailable.
if [ -z "${CURRENT_PLATFORM:-}" ]; then
  case "$(uname -s)" in
    Darwin)  CURRENT_PLATFORM='macos' ;;
    Linux*)  CURRENT_PLATFORM='linux' ;;
    *)       CURRENT_PLATFORM='unknown' ;;
  esac
fi

# Fallback functions (defined only when helpers.sh didn't provide them)
if ! command -v is_macos >/dev/null 2>&1; then
  is_macos() { [ "$CURRENT_PLATFORM" = "macos" ]; }
  is_linux() { [ "$CURRENT_PLATFORM" = "linux" ]; }
fi

# helpers.sh exports AVAILABLE_TOOLS which we don't need in an interactive shell.
unset AVAILABLE_TOOLS 2>/dev/null || true

# =============================================================================
# Antidote Plugin Manager
# =============================================================================
ANTIDOTE_HOME="${ANTIDOTE_HOME:-$HOME/.antidote}"
if [ -f "$ANTIDOTE_HOME/antidote.zsh" ] && [ -f "$HOME/.zsh_plugins.txt" ]; then
  source "$ANTIDOTE_HOME/antidote.zsh"
  antidote load "$HOME/.zsh_plugins.txt"
else
  print -ru2 -- "zshrc: Antidote not set up. Run ${DOTFILES_DIR}/zsh/deploy.sh"
fi

# Initialize completion system (zplug used to do this; antidote doesn't)
# Use -i to silently skip insecure directories (common on macOS with Homebrew
# where /opt/homebrew/share may be group-writable).
autoload -Uz compinit && compinit -i

# History substring search keybindings
# zsh-history-substring-search doesn't bind keys by itself — do it here.
# Guard against unavailable widget (e.g. Antidote not installed).
if (( $+functions[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi

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
if is_macos; then
  if [ -d /opt/homebrew/bin ]; then
    # Apple Silicon
    export PATH="/opt/homebrew/bin:$PATH"
  elif [ -d /usr/local/bin ]; then
    # Intel Mac
    export PATH="/usr/local/bin:$PATH"
  fi
elif is_linux; then
  if [ -d /home/linuxbrew/.linuxbrew/bin ]; then
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
  elif [ -d /usr/local/bin ]; then
    export PATH="/usr/local/bin:$PATH"
  fi
fi

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
if is_macos && [ -d /usr/local/var/postgres ]; then
  export PGDATA=/usr/local/var/postgres
fi

# =============================================================================
# Rust
# =============================================================================
if [ -d "$HOME/.cargo/bin" ]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# =============================================================================
# Go
# =============================================================================
if [ -d "$HOME/go" ]; then
  export GOPATH="$HOME/go"
  [ -d "$GOPATH/bin" ] && export PATH="$GOPATH/bin:$PATH"
fi

# =============================================================================
# opencode
# =============================================================================
if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi

# =============================================================================
# User binaries
# =============================================================================
# Added after the version managers so hand-written scripts win over shims.
if [ -d "$HOME/bin" ]; then
  export PATH="$HOME/bin:$PATH"
fi
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
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

# =============================================================================
# Machine-local overrides
# =============================================================================
# ~/.zshrc.local is intentionally NOT tracked in this repository. Put anything
# specific to one machine there — host addresses, API keys, work-only paths —
# so it never reaches the shared history. Sourced last, so it can override
# everything above.
if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
