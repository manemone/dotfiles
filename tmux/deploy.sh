#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

log_hr
log_info "Deploying: tmux"

FAIL=0

# --- Symlink config ---
symlink_backup "$SCRIPT_DIR/tmux.conf" "$HOME/.tmux.conf" || FAIL=1

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

if [ "$FAIL" -ne 0 ]; then
  log_error "tmux deployment completed with errors."
  exit 1
fi
log_ok "tmux deployment complete."
