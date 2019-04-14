#!/bin/sh

REPO_DIR=$(cd $(dirname $0); pwd)

ln -fs ${REPO_DIR}/.vimrc ~/.vimrc
ln -fs ${REPO_DIR}/.vimrc.plugin ~/.vimrc.plugin
ln -fs ${REPO_DIR}/.gvimrc ~/.gvimrc

if [ -d ${REPO_DIR}/.vim ]; then
  rm -rf ~/.vim
fi
ln -fs ${REPO_DIR}/.vim ~/.vim
