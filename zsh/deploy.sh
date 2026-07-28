#!/bin/sh

REPO_DIR=$(cd "$(dirname "$0")"; pwd)

. "$REPO_DIR/../shared/helpers.sh"

# Check required tools
ensure_command zsh   "Install zsh via your package manager" || exit 1
ensure_command git   "Install git via your package manager" || exit 1
ensure_command curl  "Install curl via your package manager" || exit 1

# Check optional tools (warn only)
for _tool in rbenv pyenv n mise; do
  if ! command -v "$_tool" >/dev/null 2>&1; then
    echo "[WARN] '$_tool' is not installed. Some features in .zshrc will be skipped." >&2
  fi
done
unset _tool

# Copy setting files
ln -fs "${REPO_DIR}/.zshrc"           "$HOME/.zshrc"
ln -fs "${REPO_DIR}/.zsh_plugins.txt" "$HOME/.zsh_plugins.txt"

# Install Antidote
ANTIDOTE_HOME="${ANTIDOTE_HOME:-$HOME/.antidote}"
if [ ! -d "$ANTIDOTE_HOME" ]; then
  echo "Installing Antidote plugin manager..."
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_HOME"
else
  echo "Antidote is already installed at $ANTIDOTE_HOME"
fi
