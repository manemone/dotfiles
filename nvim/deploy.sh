#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/../shared/helpers.sh"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
DEIN_CACHE="$CACHE_DIR/dein"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"

log_hr
log_info "Deploying: nvim (lazy.nvim)"

FAIL=0

# ── Prerequisite checks ──────────────────────────────────────────────────

log_info "Checking prerequisites..."

ensure_command git      "Install git via your package manager"       || exit 1
ensure_command curl     "Install curl via your package manager"      || exit 1
ensure_command nvim     "Install NeoVim 0.10+: https://neovim.io"   || exit 1

# Warn for optional but recommended tools
if ! command -v rg >/dev/null 2>&1; then
  log_warn "'ripgrep' (rg) is not installed — required for Telescope live_grep."
  if is_macos; then
    printf '       Install: brew install ripgrep\n' >&2
  elif is_linux; then
    printf '       Install: apt install ripgrep  or  brew install ripgrep\n' >&2
  fi
fi

if ! command -v fd >/dev/null 2>&1; then
  log_warn "'fd' is not installed — recommended for Telescope find_files."
  if is_macos; then
    printf '       Install: brew install fd\n' >&2
  elif is_linux; then
    printf '       Install: apt install fd-find  or  brew install fd\n' >&2
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  log_warn "'node' is not installed — required for some LSP servers (ts_ls, volar, etc.)."
  printf '       Install: mise use node@lts  or  https://nodejs.org\n' >&2
fi

if ! command -v mise >/dev/null 2>&1; then
  log_warn "'mise' is not installed — recommended for managing Python/LSP toolchains."
  printf '       Install: curl https://mise.run | sh\n' >&2
fi

# ── Create config directory ──────────────────────────────────────────────

if [ "${DRY_RUN:-0}" -eq 0 ]; then
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$DATA_DIR"
fi

# ── Symlink config files ─────────────────────────────────────────────────

symlink_backup "$SCRIPT_DIR/init.lua"            "$CONFIG_DIR/init.lua"            || FAIL=1
symlink_backup "$SCRIPT_DIR/lua"                 "$CONFIG_DIR/lua"                  || FAIL=1
symlink_backup "$SCRIPT_DIR/lazy-lock.json"      "$CONFIG_DIR/lazy-lock.json"       || FAIL=1

# ── Clean up old dein.vim symlinks ──────────────────────────────────────

if [ "${DRY_RUN:-0}" -eq 0 ]; then
  log_info "Cleaning up old dein.vim config..."

  for _f in "$CONFIG_DIR/dein.toml" "$CONFIG_DIR/dein_lazy.toml" "$CONFIG_DIR/init.vim"; do
    if [ -L "$_f" ]; then
      rm -f "$_f"
      log_info "Removed old symlink: $_f"
    elif [ -f "$_f" ]; then
      mv "$_f" "$_f.migrated-to-lazy" 2>/dev/null
      log_info "Backed up old config: $_f → $_f.migrated-to-lazy"
    fi
  done
else
  log_info "[DRY-RUN] Would remove old dein.vim symlinks & configs"
fi

# ── Clean up dein cache ─────────────────────────────────────────────────

if [ "${DRY_RUN:-0}" -eq 0 ]; then
  if [ -d "$DEIN_CACHE" ]; then
    log_info "Found old dein cache at $DEIN_CACHE"
    printf 'Remove old dein cache? [y/N] '
    read -r _answer
    case "$_answer" in
      [Yy]*)
        rm -rf "$DEIN_CACHE"
        log_ok "Old dein cache removed."
        ;;
      *)
        log_info "Dein cache kept at $DEIN_CACHE (you can remove it manually later)."
        ;;
    esac
  fi
else
  log_info "[DRY-RUN] Would offer to remove old dein cache at $DEIN_CACHE"
fi

# ── Install lazy.nvim ───────────────────────────────────────────────────

if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would install lazy.nvim plugin manager."
else
  LAZY_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"
  if [ -d "$LAZY_PATH" ]; then
    log_info "lazy.nvim is already installed at $LAZY_PATH"
  else
    log_info "Installing lazy.nvim..."
    if git clone --filter=blob:none "https://github.com/folke/lazy.nvim.git" --branch=stable "$LAZY_PATH" 2>/dev/null; then
      log_ok "lazy.nvim installed."
    else
      log_error "Failed to clone lazy.nvim. NeoVim will auto-install on first launch."
      # Not fatal — init.lua bootstraps itself
    fi
  fi
fi

# ── Python provider (Python 3 only — no more Python 2) ──────────────────

if [ "${DRY_RUN:-0}" -eq 1 ]; then
  log_info "[DRY-RUN] Would install neovim Python 3 provider"
else
  log_info "Setting up Python 3 provider for Neovim..."
  _python3=""
  if command -v mise >/dev/null 2>&1; then
    _python3=$(mise where python 2>/dev/null || true)
    if [ -n "$_python3" ]; then
      if "$_python3/bin/pip" install --quiet pynvim 2>/dev/null; then
        log_ok "pynvim installed via mise Python at $_python3"
      else
        log_warn "Failed to install pynvim via mise Python. Falling back to system pip."
        _python3=""  # clear to trigger system pip fallback
      fi
    fi
  fi
  if [ -z "$_python3" ]; then
    # Fall back to any available pip3
    if command -v pip3 >/dev/null 2>&1; then
      pip3 install --quiet --user pynvim 2>/dev/null && log_ok "pynvim installed via system pip3"
    elif command -v pip >/dev/null 2>&1; then
      pip install --quiet --user pynvim 2>/dev/null && log_ok "pynvim installed via system pip"
    else
      log_warn "No Python/pip found. Python provider not set up."
      log_warn 'Install Python 3 via mise: mise use python@latest'
    fi
  fi
fi

# ── Ruby provider (optional) ─────────────────────────────────────────────

if command -v gem >/dev/null 2>&1; then
  if [ "${DRY_RUN:-0}" -eq 0 ]; then
    gem install --user-install neovim 2>/dev/null || log_warn "gem install neovim failed (Ruby may not be set up)"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────

if [ "$FAIL" -ne 0 ]; then
  log_error "nvim deployment completed with errors."
  exit 1
fi

log_ok "nvim deployment complete."
echo ""
log_info "Next steps:"
log_info "  1. Open NeoVim — plugins will auto-install via lazy.nvim"
log_info "  2. Run :Mason to review/install LSP servers"
log_info "  3. Run :checkhealth for diagnostics"
log_info "  4. See README.md for detailed setup"
