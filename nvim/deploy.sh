#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

log_hr
log_info "Deploying: nvim"

FAIL=0

# --- Required tools ---
ensure_command curl "Install curl via your package manager" || exit 1
ensure_command git  "Install git via your package manager"  || exit 1

# --- Optional: mise (warn only — not called by this script) ---
if ! command -v mise >/dev/null 2>&1; then
  log_warn "'mise' is not installed. Install: curl https://mise.run | sh"
fi

# --- Create config directory ---
if [ "${DRY_RUN:-0}" -eq 0 ]; then
  mkdir -p "$CONFIG_DIR"
fi

# --- Symlink config files ---
symlink_backup "$SCRIPT_DIR/init.vim"       "$CONFIG_DIR/init.vim"       || FAIL=1
symlink_backup "$SCRIPT_DIR/dein.toml"      "$CONFIG_DIR/dein.toml"      || FAIL=1
symlink_backup "$SCRIPT_DIR/dein_lazy.toml" "$CONFIG_DIR/dein_lazy.toml" || FAIL=1

# --- Install dein.vim ---
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would install dein.vim"
else
  log_info "Installing dein.vim plugin manager..."
  _installer=$(mktemp "${TMPDIR:-/tmp}/dein_installer.XXXXXX") || {
    log_error "Failed to create temporary file for dein installer."
    exit 1
  }
  if ! curl -fsSL https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh -o "$_installer"; then
    log_error "Failed to download dein.vim installer."
    rm -f "$_installer"
    exit 1
  fi
  if sh "$_installer" "$HOME/.cache/dein" >/dev/null 2>&1; then
    log_ok "dein.vim installed."
  else
    log_error "dein.vim installer failed."
    rm -f "$_installer"
    exit 1
  fi
  rm -f "$_installer"
fi

# --- Python / Ruby Neovim providers ---
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would install neovim Python/Ruby providers"
else
  if [ -n "${PYENV_VIRTUALENV_INIT:-}" ]; then
    log_info "Setting up pyenv-based Neovim Python providers..."
    pyenv install 2.7.16
    pyenv virtualenv 2.7.16 neovim2
    pyenv activate neovim2
    pyenv exec pip install neovim
    pyenv which python

    pyenv install 3.8.10
    pyenv virtualenv 3.8.10 neovim3
    pyenv activate neovim3
    pyenv exec pip install neovim
    pyenv which python
  else
    log_info "Installing neovim Python provider via pip..."
    pip install neovim
  fi
  gem install neovim 2>/dev/null || log_warn "gem install neovim failed (Ruby may not be set up)"
fi

if [ "$FAIL" -ne 0 ]; then
  log_error "nvim deployment completed with errors."
  exit 1
fi
log_ok "nvim deployment complete."
