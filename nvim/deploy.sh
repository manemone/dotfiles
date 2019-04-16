#!/bin/sh

REPO_DIR=$(cd $(dirname $0); pwd)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

mkdir -p $CONFIG_DIR

# Copy setting files
ln -fs ${REPO_DIR}/init.vim $CONFIG_DIR/init.vim
ln -fs ${REPO_DIR}/dein.toml $CONFIG_DIR/dein.toml
ln -fs ${REPO_DIR}/dein_lazy.toml $CONFIG_DIR/dein_lazy.toml

# Install dein.vim
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > /tmp/dein_installer.sh
sh /tmp/dein_installer.sh ~/.cache/dein > /dev/null 2>&1

# Install necessary software
if [ -n "$PYENV_VIRTUALENV_INIT " ]; then
  pyenv install 2.7.16
  pyenv virtualenv 2.7.16 neovim2
  pyenv activate neovim2
  pip2 install neovim
  pyenv which python

  pyenv install 3.7.3
  pyenv virtualenv 3.7.3 neovim3
  pyenv activate neovim3
  pip install neovim
  pyenv which python
else
  pip install neovim
fi
gem install neovim
