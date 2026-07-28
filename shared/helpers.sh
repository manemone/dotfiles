#!/bin/sh

case "$(uname -s)" in
  Darwin)
    CURRENT_PLATFORM='Mac'
    ;;
  Linux*)
    CURRENT_PLATFORM='Linux'
    ;;
  MINGW32_NT*)
    CURRENT_PLATFORM='Cygwin'
    ;;
  *)
    CURRENT_PLATFORM='Unknown'
    ;;
esac

# is_wsl
# Detect if running under Windows Subsystem for Linux (WSL).
# Returns 0 if WSL, 1 otherwise.
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  grep -qi microsoft /proc/version 2>/dev/null
}

# ensure_command <cmd> [hint]
# Check if a command is available, print install instructions if not.
# Returns 0 if found, 1 if not found.
ensure_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  echo "[ERROR] '$1' is not installed." >&2
  if [ -n "$2" ]; then
    echo "Install: $2" >&2
  fi
  return 1
}
