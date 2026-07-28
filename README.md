# dotfiles
Easily deployable setting files

# Prerequisites
This project uses [mise](https://mise.jdx.dev/) to manage tool versions (Python, Node.js, Ruby, Rust, etc.).

## Install mise
```sh
curl https://mise.run | sh
```
Or via package manager:
- macOS: `brew install mise`
- Linux: `apt install mise`

## Bootstrap
After installing mise, run the following to install all required tools:
```sh
mise install
```

Platform-specific packages are also provided:
- macOS: `brew bundle --file Brewfile`
- Linux/WSL: `sudo apt install $(cat apt-packages.txt)`

# Supported tools
- NeoVim
- Z Shell

# After cloning this repo
Follow the instructions in README.md in each subdirectory.
Most of them has some custom setup script.
