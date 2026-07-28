# Zsh Setup

## Requirements

- **Zsh** (5.4.2+) — required by Antidote and Pure
- **Git** — for plugin installation

## What's Included

| Feature | Details |
|---|---|
| Plugin manager | [Antidote](https://github.com/mattmc3/antidote) |
| Theme | [Pure](https://github.com/sindresorhus/pure) |
| Plugins | syntax highlighting, autosuggestions, history search, completions, 256color |
| Version managers | rbenv, pyenv, n, mise (auto-detected, skipped if not installed) |
| Editor | NeoVim aliases (`vim`/`vi` → `nvim`, skipped if not installed) |
| Cloud | Google Cloud SDK (auto-detected) |
| Language | Rust, Ruby, Python, Node.js PATH setup (skipped if not installed) |

## Installation

### 1. Install Zsh

#### macOS
```bash
brew install zsh
```

#### Linux (Debian/Ubuntu)
```bash
sudo apt install zsh
```

#### WSL (Windows Subsystem for Linux)
```bash
sudo apt install zsh
```

### 2. Set Zsh as default shell

First, register the shell path if needed (macOS with Homebrew):

```bash
# macOS: Homebrew zsh is not in /etc/shells by default
sudo sh -c "echo $(brew --prefix)/bin/zsh >> /etc/shells"
chsh -s "$(brew --prefix)/bin/zsh"
```

```bash
# Linux / WSL
chsh -s "$(which zsh)"
```

### 3. Run the deploy script

```bash
cd zsh
./deploy.sh
```

The script will:
- Create symlinks for `.zshrc` and `.zsh_plugins.txt`
- Install [Antidote](https://github.com/mattmc3/antidote) via `git clone`
- Warn if optional tools (rbenv, pyenv, n, mise) are missing

### 4. Open a new shell

```bash
exec zsh
```

Antidote will automatically clone plugins declared in `~/.zsh_plugins.txt` on first run.

## Platform Notes

### macOS
- Homebrew paths are auto-detected for both Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`)
- PostgreSQL `PGDATA` is set to `/usr/local/var/postgres` if the directory exists

### Linux
- Homebrew path defaults to `/home/linuxbrew/.linuxbrew`
- PostgreSQL `PGDATA` is **not** set

### WSL
- Treated as Linux; macOS-specific settings (PostgreSQL PGDATA) are skipped
- Works the same as native Linux otherwise

## Plugin Management

Plugins are declared in `~/.zsh_plugins.txt` (symlinked from this repo).
To add or remove a plugin, edit `zsh/.zsh_plugins.txt` and reload:

```bash
source ~/.zshrc
```

Or start a new shell.

### Updating plugins

Antidote does **not** update plugins automatically. To update all plugins:

```bash
antidote update
```

### Custom install location

Set the `ANTIDOTE_HOME` environment variable to change where Antidote is installed
(default: `~/.antidote`). This must be set **before** running `deploy.sh` so that
Antidote is cloned to the custom path:

```bash
export ANTIDOTE_HOME="$HOME/.local/share/antidote"
./deploy.sh
```

The same variable must also be visible when `.zshrc` is sourced. To make it permanent,
add it to your `~/.zshenv` (sourced before `.zshrc`):

```bash
echo 'export ANTIDOTE_HOME="$HOME/.local/share/antidote"' >> ~/.zshenv
```
