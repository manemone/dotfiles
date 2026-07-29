#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

log_hr
log_info "Deploying: claude (Claude Code config)"

FAIL=0

# --- Ensure ~/.claude exists ---
CLAUDE_DIR="$HOME/.claude"

if [ ! -d "$CLAUDE_DIR" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would create directory: $CLAUDE_DIR"
  else
    log_info "Creating directory: $CLAUDE_DIR"
    mkdir -p "$CLAUDE_DIR" || {
      log_error "Failed to create directory: $CLAUDE_DIR"
      exit 1
    }
    log_ok "Created: $CLAUDE_DIR"
  fi
fi

# --- Symlink config files ---
symlink_backup "$SCRIPT_DIR/CLAUDE.md"    "$CLAUDE_DIR/CLAUDE.md"    || FAIL=1
symlink_backup "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json" || FAIL=1

if [ "$FAIL" -ne 0 ]; then
  log_error "claude deployment completed with errors."
  exit 1
fi
log_ok "claude deployment complete."
