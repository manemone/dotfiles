#!/bin/sh

REPO_DIR=$(cd $(dirname $0); pwd)
CONFIG_DIR=$HOME

source $REPO_DIR/../shared/helpers.sh

# Copy setting files
ln -fs ${REPO_DIR}/tmux.conf $CONFIG_DIR/.tmux.conf

# Install necessary software
case $CURRENT_PLATFORM in
  "Mac")
    brew install tmux reattach-to-user-namespace
    ;;
esac
