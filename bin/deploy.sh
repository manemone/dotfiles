#!/bin/sh

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
# shellcheck source=SCRIPTDIR/../shared/helpers.sh
. "$SCRIPT_DIR/../shared/helpers.sh"

log_hr
log_info "Deploying: bin"

FAIL=0

# --- Ensure ~/bin exists ---
BIN_DIR="$HOME/bin"

if [ ! -d "$BIN_DIR" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would create directory: $BIN_DIR"
  else
    log_info "Creating directory: $BIN_DIR"
    mkdir -p "$BIN_DIR" || {
      log_error "Failed to create directory: $BIN_DIR"
      exit 1
    }
    log_ok "Created: $BIN_DIR"
  fi
fi

# --- Symlink scripts into ~/bin ---
symlink_backup "$SCRIPT_DIR/ocw" "$BIN_DIR/ocw" || FAIL=1
symlink_backup "$SCRIPT_DIR/claude-ds" "$BIN_DIR/claude-ds" || FAIL=1

if [ "$FAIL" -ne 0 ]; then
  log_error "bin deployment completed with errors."
  exit 1
fi
log_ok "bin deployment complete."
