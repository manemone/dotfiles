#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

log_hr
log_info "Deploying: nvim"

# --- Required tools ---
ensure_command mise "curl https://mise.run | sh" || exit 1

# --- Create config directory ---
if [ "${DRY_RUN:-0}" -eq 0 ]; then
  mkdir -p "$CONFIG_DIR"
fi

# --- Symlink config files ---
symlink_backup "$SCRIPT_DIR/init.vim"       "$CONFIG_DIR/init.vim"
symlink_backup "$SCRIPT_DIR/dein.toml"      "$CONFIG_DIR/dein.toml"
symlink_backup "$SCRIPT_DIR/dein_lazy.toml" "$CONFIG_DIR/dein_lazy.toml"

# --- Install dein.vim ---
if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would install dein.vim"
else
  log_info "Installing dein.vim plugin manager..."
  curl -fsSL https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > /tmp/dein_installer.sh
  sh /tmp/dein_installer.sh ~/.cache/dein > /dev/null 2>&1
  log_ok "dein.vim installed."
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

log_ok "nvim deployment complete."
