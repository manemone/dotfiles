#!/bin/sh

REPO_DIR=$(cd "$(dirname "$0")"; pwd)

. "$REPO_DIR/../shared/helpers.sh"

# Check required tools
ensure_command zsh   "Install zsh via your package manager" || exit 1
ensure_command git   "Install git via your package manager" || exit 1

# Check optional tools (warn only)
for _tool in rbenv pyenv n; do
  if ! command -v "$_tool" >/dev/null 2>&1; then
    echo "[WARN] '$_tool' is not installed. Related settings in .zshrc will be skipped." >&2
  fi
done
unset _tool

# mise requires a separate message because the install hint differs
if ! command -v mise >/dev/null 2>&1; then
  echo "[WARN] 'mise' is not installed. Install: curl https://mise.run | sh" >&2
fi

# Copy setting files
ln -fs "${REPO_DIR}/.zshrc"           "$HOME/.zshrc"
ln -fs "${REPO_DIR}/.zsh_plugins.txt" "$HOME/.zsh_plugins.txt"

# Install Antidote
ANTIDOTE_HOME="${ANTIDOTE_HOME:-$HOME/.antidote}"
if [ ! -f "$ANTIDOTE_HOME/antidote.zsh" ]; then
  echo "Installing Antidote plugin manager..."
  # Only remove if it looks like a (broken) antidote clone or is empty.
  if [ -d "$ANTIDOTE_HOME" ]; then
    if [ -d "$ANTIDOTE_HOME/.git" ]; then
      # Git repo — likely a prior antidote clone. Safe to remove.
      rm -rf "$ANTIDOTE_HOME"
    elif [ -z "$(ls -A "$ANTIDOTE_HOME" 2>/dev/null)" ]; then
      # Empty directory — safe to remove.
      rmdir "$ANTIDOTE_HOME"
    else
      echo "[ERROR] $ANTIDOTE_HOME exists but is not an Antidote installation." >&2
      echo "Remove it manually or set ANTIDOTE_HOME to a different path." >&2
      exit 1
    fi
  fi
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_HOME" || {
    echo "[ERROR] Failed to clone Antidote into $ANTIDOTE_HOME" >&2
    exit 1
  }
else
  echo "Antidote is already installed at $ANTIDOTE_HOME"
fi
