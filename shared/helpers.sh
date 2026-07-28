#!/bin/sh
#
# shared/helpers.sh — Unified helpers sourced by every deploy script.
# Keep functions self-contained and side-effect free where possible.
# This file uses POSIX sh (no bashisms).

# ── Platform detection ────────────────────────────────────────────────

case "$(uname -s)" in
  Darwin)
    CURRENT_PLATFORM='macos'
    ;;
  Linux*)
    CURRENT_PLATFORM='linux'
    ;;
  MINGW32_NT*)
    CURRENT_PLATFORM='cygwin'
    ;;
  *)
    CURRENT_PLATFORM='unknown'
    ;;
esac

is_macos() { [ "$CURRENT_PLATFORM" = "macos" ]; }
is_linux() { [ "$CURRENT_PLATFORM" = "linux" ]; }

# is_wsl
# Returns 0 if running under Windows Subsystem for Linux, 1 otherwise.
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  grep -qi microsoft /proc/version 2>/dev/null
}

# Canonical list of available tools.  deploy-all.sh and uninstall.sh
# both source this file, so the list is defined once.
AVAILABLE_TOOLS="zsh nvim tmux"

# ── Logging (colourised when the output fd is a terminal) ─────────────

# _can_color <fd>
# Returns 0 if fd is a terminal and NO_COLOR is unset.
_can_color() {
  [ -t "$1" ] && [ -z "${NO_COLOR:-}" ]
}

log_info() {
  if _can_color 1; then
    printf '\033[36m[INFO]\033[m %s\n' "$*"
  else
    printf '[INFO] %s\n' "$*"
  fi
}

log_warn() {
  if _can_color 2; then
    printf '\033[33m[WARN]\033[m %s\n' "$*" >&2
  else
    printf '[WARN] %s\n' "$*" >&2
  fi
}

log_error() {
  if _can_color 2; then
    printf '\033[31m[ERROR]\033[m %s\n' "$*" >&2
  else
    printf '[ERROR] %s\n' "$*" >&2
  fi
}

log_ok() {
  if _can_color 1; then
    printf '\033[32m[OK]\033[m %s\n' "$*"
  else
    printf '[OK] %s\n' "$*"
  fi
}

# Print a horizontal rule (ASCII for portability, 50 chars wide).
log_hr() {
  printf '%s\n' '--------------------------------------------------'
}

# ── Command helpers ───────────────────────────────────────────────────

# ensure_command <cmd> [hint]
# Check if a command is available.  If not, print an error + optional
# install hint and return 1.
# In dry-run mode, missing commands are noted but do not cause a failure
# (so the full plan is visible).
ensure_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log_warn "[DRY-RUN] '$1' is not installed — would fail during real deploy."
    if [ -n "${2:-}" ]; then
      printf '        Install: %s\n' "$2" >&2
    fi
    return 0
  fi
  log_error "'$1' is not installed."
  if [ -n "${2:-}" ]; then
    printf '       Install: %s\n' "$2" >&2
  fi
  return 1
}

# ── Homebrew prefix ───────────────────────────────────────────────────

# get_brew_prefix
# Print the Homebrew prefix for the current architecture.
# macOS:  /opt/homebrew (Apple Silicon) or /usr/local (Intel)
# Linux:  /home/linuxbrew/.linuxbrew
get_brew_prefix() {
  if command -v brew >/dev/null 2>&1; then
    brew --prefix 2>/dev/null && return 0
  fi
  # Best guess when brew is not on PATH yet
  if is_macos; then
    if [ "$(uname -m)" = "arm64" ]; then
      printf '/opt/homebrew'
    else
      printf '/usr/local'
    fi
  elif is_linux; then
    printf '/home/linuxbrew/.linuxbrew'
  else
    printf '/usr/local'
  fi
}

# ── Filesystem helpers ────────────────────────────────────────────────

# _backup_dst <dst>
# Print a safe backup path for dst.  If dst.backup doesn't exist, use it
# as-is; otherwise append a timestamp + PID to avoid overwriting a previous
# backup (PID included to prevent same-second collisions).
_backup_dst() {
  _bd="$1.backup"
  if [ ! -e "$_bd" ] && [ ! -L "$_bd" ]; then
    printf '%s' "$_bd"
  else
    printf '%s.%s.%s' "$_bd" "$(date +%Y%m%d%H%M%S)" "$$"
  fi
}

# symlink_backup <src> <dst>
# Create a symlink dst → src.  If dst already exists (and is not already
# the correct symlink), move it to a backup path first.
# If DRY_RUN is set to 1, only print what would be done.
# If BACKUP is set to 0, existing files are removed instead of backed up.
symlink_backup() {
  _src="$1"
  _dst="$2"

  # Already correct?
  if [ -L "$_dst" ] && [ "$(readlink "$_dst")" = "$_src" ]; then
    log_info "Already linked: $_dst → $_src"
    return 0
  fi

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    if [ -e "$_dst" ] || [ -L "$_dst" ]; then
      if [ "${BACKUP:-1}" -eq 0 ]; then
        printf '[DRY-RUN] rm -f %s\n' "$_dst"
      else
        printf '[DRY-RUN] mv %s %s\n' "$_dst" "$(_backup_dst "$_dst")"
      fi
    fi
    printf '[DRY-RUN] ln -fs %s %s\n' "$_src" "$_dst"
    return 0
  fi

  # Ensure parent directory exists
  _parent="$(dirname "$_dst")"
  if [ ! -d "$_parent" ]; then
    mkdir -p "$_parent" || {
      log_error "Failed to create directory: $_parent"
      return 1
    }
  fi

  # Handle existing file / symlink
  if [ -e "$_dst" ] || [ -L "$_dst" ]; then
    if [ "${BACKUP:-1}" -eq 0 ]; then
      log_warn "Removing existing (backup disabled): $_dst"
      rm -f "$_dst" || {
        log_error "Failed to remove: $_dst"
        return 1
      }
    else
      _backup_path="$(_backup_dst "$_dst")"
      log_warn "Backing up existing: $_dst → $_backup_path"
      mv "$_dst" "$_backup_path" || {
        log_error "Failed to back up: $_dst"
        return 1
      }
    fi
  fi

  ln -fs "$_src" "$_dst" || {
    log_error "Failed to symlink: $_src → $_dst"
    return 1
  }
  log_ok "Linked: $_dst → $_src"
  return 0
}

# symlink_restore <dst>
# Remove the symlink at dst and restore from a .backup* file if one exists.
# If dst is a real file (not a symlink), skip to avoid overwriting user data.
# Restores the *original* backup (dst.backup without timestamp) if available;
# otherwise falls back to the oldest timestamped backup.
# Used by uninstall.sh.
symlink_restore() {
  _dst="$1"

  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    if [ -L "$_dst" ]; then
      printf '[DRY-RUN] rm %s\n' "$_dst"
    elif [ -e "$_dst" ]; then
      printf '[DRY-RUN] (skip — real file exists at %s)\n' "$_dst"
    fi
    if [ -e "$_dst.backup" ] || [ -L "$_dst.backup" ]; then
      printf '[DRY-RUN] mv %s.backup %s\n' "$_dst" "$_dst"
    fi
    return 0
  fi

  _fail=0

  if [ -L "$_dst" ]; then
    if rm "$_dst"; then
      log_info "Removed symlink: $_dst"
    else
      log_error "Failed to remove symlink: $_dst"
      _fail=1
    fi
  elif [ -e "$_dst" ]; then
    log_warn "Skipping restore — real file exists at $_dst (not a symlink)"
    return 0
  fi

  # Restore the *original* backup (dst.backup) first; if that doesn't exist,
  # pick the oldest timestamped backup (first in glob order = earliest).
  # Use -e || -L to also match backup files that are symlinks or broken symlinks.
  _restore=""
  if [ -e "$_dst.backup" ] || [ -L "$_dst.backup" ]; then
    _restore="$_dst.backup"
  else
    for _cand in "$_dst.backup."*; do
      [ -e "$_cand" ] || [ -L "$_cand" ] || continue
      _restore="$_cand"
      break
    done
  fi

  if [ -n "$_restore" ]; then
    if mv "$_restore" "$_dst"; then
      log_ok "Restored backup: $_dst (from $_restore)"
    else
      log_error "Failed to restore backup: $_restore → $_dst"
      _fail=1
    fi
  fi

  return "$_fail"
}
