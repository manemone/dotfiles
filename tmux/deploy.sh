#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

log_hr
log_info "Deploying: tmux"

# --- Symlink config ---
symlink_backup "$SCRIPT_DIR/tmux.conf" "$HOME/.tmux.conf"

# --- Install tmux (macOS only via Homebrew) ---
if is_macos; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would run: brew install tmux reattach-to-user-namespace"
  else
    if command -v tmux >/dev/null 2>&1; then
      log_info "tmux is already installed."
    else
      log_info "Installing tmux via Homebrew..."
      brew install tmux reattach-to-user-namespace
      log_ok "tmux installed."
    fi
  fi
elif ! command -v tmux >/dev/null 2>&1; then
  log_warn "tmux is not installed. Install via your package manager."
fi

log_ok "tmux deployment complete."
