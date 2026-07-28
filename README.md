# dotfiles
Easily deployable setting files

# Prerequisites
This project uses [mise](https://mise.jdx.dev/) to manage tool versions
(Python, Node.js, Ruby, Rust, neovim, ripgrep, fd, lazygit).

## 1. Install mise
```sh
curl https://mise.run | sh
```
macOS alternative: `brew install mise`
For other Linux installation options, see https://mise.jdx.dev/getting-started.html.

## 2. Clone and bootstrap
```sh
git clone https://github.com/manemone/dotfiles.git ~/dotfiles
cd ~/dotfiles
mise trust
mise install
```

Install platform-specific system packages:
- macOS: `brew bundle --file Brewfile`
- Linux/WSL: `sudo apt install $(cat apt-packages.txt)`


# Supported tools
- NeoVim
- Z Shell

# After cloning this repo
Follow the instructions in README.md in each subdirectory.
Most of them has some custom setup script.
