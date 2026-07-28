# dotfiles
Easily deployable setting files

# Prerequisites
This project uses [mise](https://mise.jdx.dev/) to manage tool versions
(Python, Node.js, Ruby, Rust, neovim, ripgrep, fd, lazygit).

## Install mise
```sh
curl https://mise.run | sh
```
macOS: `brew install mise`
Linux: see https://mise.jdx.dev/getting-started.html for installation options.

## Bootstrap
After installing mise, run the following to install all required tools:
```sh
mise trust
mise install
```

Platform-specific system packages are also needed:
- macOS: `brew bundle --file Brewfile`
- Linux/WSL: `sudo apt install $(cat apt-packages.txt)`

> **Note**: mise is not yet activated in the shell configuration. Currently
> python/ruby/node from existing pyenv/rbenv/n will take precedence over mise.
> Shell integration will be added in a follow-up PR.

# Supported tools
- NeoVim
- Z Sehll

# After cloning this repo
Follow the instructions in README.md in each subdirectory.
Most of them has some custom setup script.
