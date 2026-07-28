#!/bin/sh

REPO_DIR=$(cd $(dirname $0); pwd)

source $REPO_DIR/../shared/helpers.sh
ensure_command mise

# Copy setting files
ln -fs ${REPO_DIR}/.zshrc $HOME/.zshrc

# Install zplug
curl -sL --proto-redir -all,https https://raw.githubusercontent.com/zplug/installer/master/installer.zsh| zsh
