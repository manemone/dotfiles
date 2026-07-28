#!/bin/sh

if [ "$(uname)" == 'Darwin' ]; then
  CURRENT_PLATFORM='Mac'
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  CURRENT_PLATFORM='Linux'
elif [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then
  CURRENT_PLATFORM='Cygwin'
else
  CURRENT_PLATFORM='Unknown'
fi

# Check if a command is available, print install instructions if not
ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] '$1' is not installed."
    echo "Install it with one of the following:"
    case "$1" in
      mise)
        echo "  curl https://mise.run | sh"
        echo "  or: brew install mise"
        echo "  or: apt install mise"
        ;;
      *)
        echo "  (no install hint for '$1')"
        ;;
    esac
    return 1
  fi
  return 0
}
