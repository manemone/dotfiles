#!/bin/sh

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
# shellcheck source=SCRIPTDIR/../shared/helpers.sh
. "$SCRIPT_DIR/../shared/helpers.sh"

# --- Resolve distribution source (current generation) ---
# See AGENTS.md "デプロイの仕組み": standalone runs default to `current`;
# deploy-all.sh overrides this with the generation it just created.
if [ -z "${DOTFILES_DEPLOY_SRC:-}" ]; then
  DOTFILES_DEPLOY_SRC="$(dotfiles_current_link)"
  if [ ! -e "$DOTFILES_DEPLOY_SRC" ]; then
    log_error "No distributed generation found (current does not exist yet)."
    log_error "Run ./deploy-all.sh from the repo root first."
    exit 1
  fi
fi

log_hr
log_info "Deploying: tmux"

FAIL=0

# --- Symlink config ---
symlink_backup "$DOTFILES_DEPLOY_SRC/tmux/tmux.conf" "$HOME/.tmux.conf" || FAIL=1

# --- Install tmux ---
install_tmux_macos() {
  if command -v tmux >/dev/null 2>&1; then
    log_info "tmux is already installed ($(tmux -V 2>&1))."
    return 0
  fi
  log_info "Installing tmux via Homebrew..."
  brew install tmux reattach-to-user-namespace || {
    log_error "Failed to install tmux via Homebrew."
    return 1
  }
  log_ok "tmux installed."
}

install_tmux_linux() {
  if command -v tmux >/dev/null 2>&1; then
    log_info "tmux is already installed ($(tmux -V 2>&1))."
    return 0
  fi
  # Prefer apt on Debian/Ubuntu; fall back to Homebrew
  if command -v apt-get >/dev/null 2>&1; then
    log_info "Installing tmux via apt..."
    if ! sudo apt-get update -qq || ! sudo apt-get install -y tmux; then
      log_error "Failed to install tmux via apt."
      return 1
    fi
    log_ok "tmux installed via apt."
  elif command -v brew >/dev/null 2>&1; then
    log_info "Installing tmux via Homebrew (Linux)..."
    brew install tmux || {
      log_error "Failed to install tmux via Homebrew."
      return 1
    }
    log_ok "tmux installed via Homebrew."
  else
    log_warn "Could not install tmux automatically."
    log_warn "Install manually: https://github.com/tmux/tmux/wiki/Installing"
    return 1
  fi
}

if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would install tmux for platform: $CURRENT_PLATFORM"
else
  if is_macos; then
    install_tmux_macos || FAIL=1
  elif is_linux; then
    install_tmux_linux || FAIL=1
    if is_wsl; then
      log_info "WSL detected: for clipboard integration, install wl-clipboard:"
      log_info "  sudo apt install wl-clipboard"
      log_info "  WSLg / Windows Terminal users get automatic clipboard passthrough."
    fi
  else
    if ! command -v tmux >/dev/null 2>&1; then
      log_warn "tmux is not installed. Install via your package manager."
    fi
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "tmux deployment completed with errors."
  exit 1
fi
log_ok "tmux deployment complete."
