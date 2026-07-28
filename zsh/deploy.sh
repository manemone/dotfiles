#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

log_hr
log_info "Deploying: zsh"

FAIL=0

# --- Required tools ---
ensure_command zsh "Install zsh via your package manager" || exit 1
ensure_command git "Install git via your package manager" || exit 1

# --- Optional tools (warn only) ---
for _tool in rbenv pyenv n; do
  if ! command -v "$_tool" >/dev/null 2>&1; then
    log_warn "'$_tool' is not installed. Related settings in .zshrc will be skipped."
  fi
done
unset _tool

if ! command -v mise >/dev/null 2>&1; then
  log_warn "'mise' is not installed. Install: curl https://mise.run | sh"
fi

# --- Symlink config files ---
symlink_backup "$SCRIPT_DIR/.zshrc"           "$HOME/.zshrc"           || FAIL=1
symlink_backup "$SCRIPT_DIR/.zsh_plugins.txt" "$HOME/.zsh_plugins.txt" || FAIL=1

# --- Install Antidote plugin manager ---
ANTIDOTE_HOME="${ANTIDOTE_HOME:-$HOME/.antidote}"
if [ ! -f "$ANTIDOTE_HOME/antidote.zsh" ]; then
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_info "[DRY-RUN] Would install Antidote to $ANTIDOTE_HOME"
  else
    log_info "Installing Antidote plugin manager..."
    if [ -d "$ANTIDOTE_HOME" ]; then
      if [ -d "$ANTIDOTE_HOME/.git" ]; then
        rm -rf "$ANTIDOTE_HOME"
      elif [ -z "$(ls -A "$ANTIDOTE_HOME" 2>/dev/null)" ]; then
        rmdir "$ANTIDOTE_HOME"
      else
        log_error "$ANTIDOTE_HOME exists but is not an Antidote installation."
        log_error "Remove it manually or set ANTIDOTE_HOME to a different path."
        exit 1
      fi
    fi
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_HOME" || {
      log_error "Failed to clone Antidote into $ANTIDOTE_HOME"
      exit 1
    }
    log_ok "Antidote installed to $ANTIDOTE_HOME"
  fi
else
  log_info "Antidote is already installed at $ANTIDOTE_HOME"
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "zsh deployment completed with errors."
  exit 1
fi
log_ok "zsh deployment complete."
