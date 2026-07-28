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
