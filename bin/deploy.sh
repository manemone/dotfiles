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
symlink_backup "$DOTFILES_DEPLOY_SRC/bin/ocw" "$BIN_DIR/ocw" || FAIL=1
symlink_backup "$DOTFILES_DEPLOY_SRC/bin/claude-ds" "$BIN_DIR/claude-ds" || FAIL=1
symlink_backup "$DOTFILES_DEPLOY_SRC/bin/ocw-meter" "$BIN_DIR/ocw-meter" || FAIL=1

if [ "$FAIL" -ne 0 ]; then
  log_error "bin deployment completed with errors."
  exit 1
fi
log_ok "bin deployment complete."
