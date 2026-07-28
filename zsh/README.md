# Zsh Setup

## 1. Requirements

| Tool | Minimum Version | Why |
|---|---|---|
| **Zsh** | 5.4.2+ | Required by Antidote and Pure theme |
| **Git** | any | Plugin installation (Antidote clones via git) |
| **mise** | any (recommended) | Runtime manager; `.zshrc` auto-activates it if installed |

### Install Zsh

**macOS (Apple Silicon / Intel)**
```bash
brew install zsh
```

**Linux (Ubuntu/Debian)**
```bash
sudo apt update && sudo apt install zsh
```

**WSL2 (Windows Subsystem for Linux)**
```bash
sudo apt update && sudo apt install zsh
```

After installation, set Zsh as your default shell:

```bash
# macOS: register Homebrew zsh in /etc/shells first
sudo sh -c "echo $(brew --prefix)/bin/zsh >> /etc/shells"
chsh -s "$(brew --prefix)/bin/zsh"

# Linux / WSL
chsh -s "$(which zsh)"
```

## 2. Quick Start

```bash
cd ~/.dotfiles/zsh
./deploy.sh
exec zsh
```

The deploy script:
- Symlinks `.zshrc` → `~/.zshrc`
- Symlinks `.zsh_plugins.txt` → `~/.zsh_plugins.txt`
- Clones [Antidote](https://github.com/mattmc3/antidote) to `~/.antidote` (or `$ANTIDOTE_HOME`)
- Warns if optional tools (rbenv, pyenv, n, mise) are missing

On first shell launch, Antidote automatically clones all plugins declared in `~/.zsh_plugins.txt`.

## 3. What's Included

### Theme & Plugins

Plugins are loaded in order; `syntax-highlighting` must be second-to-last and `history-substring-search` must be last.

| Order | Feature | Plugin |
|---|---|---|
| 1 | Theme | [Pure](https://github.com/sindresorhus/pure) — minimal, async prompt |
| 2 | Completions | `zsh-users/zsh-completions` |
| 3 | 256-color | `chrissicool/zsh-256color` |
| 4 | Autosuggestions | `zsh-users/zsh-autosuggestions` |
| 5 | Syntax highlighting | `zsh-users/zsh-syntax-highlighting` (must be second-to-last) |
| 6 | History search | `zsh-users/zsh-history-substring-search` (must be last) |

### Aliases

| Alias | Expands to |
|---|---|
| `ll` | `ls -alF` |
| `la` | `ls -A` |
| `l` | `ls -CF` |
| `vim`, `vi` | `nvim` (only if NeoVim is installed) |
| `be`, `bx` | `bundle exec` |
| `webrick` | One-liner HTTP server on port 8000 |

### Version Managers (auto-detected)

`.zshrc` checks for each tool at shell startup and skips it silently if not installed:

| Tool | What it manages | Config block |
|---|---|---|
| **mise** | Python, Node.js, Ruby, Rust, NeoVim, tools | `eval "$(mise activate zsh)"` |
| **rbenv** | Ruby | `eval "$(rbenv init -)"` |
| **pyenv** | Python | `eval "$(pyenv init --path)"` + `$(pyenv init -)` + virtualenv |
| **n** | Node.js | `N_PREFIX` and PATH setup |

### Platform-Specific Settings

| Setting | macOS | Linux / WSL |
|---|---|---|
| Homebrew PATH | `/opt/homebrew/bin` (arm64) or `/usr/local/bin` (x86_64) | `/home/linuxbrew/.linuxbrew/bin` |
| PostgreSQL `PGDATA` | `/usr/local/var/postgres` (if directory exists) | Not set |
| Rust PATH | `$HOME/.cargo/bin` | `$HOME/.cargo/bin` |
| Google Cloud SDK | Auto-detected (Homebrew Cask + manual install paths) | Auto-detected |

### History

- File: `~/.zsh_history`
- Size: 10,000 entries
- Options: `SHARE_HISTORY`, `HIST_IGNORE_DUPS`, `HIST_IGNORE_SPACE`, `HIST_VERIFY`

## 4. Customization

### Adding / Removing Plugins

Edit `zsh/.zsh_plugins.txt` in this repo and reload:

```bash
source ~/.zshrc
# or start a new shell
```

### Updating Plugins

Antidote does **not** auto-update plugins. To update all plugins:

```bash
antidote update
```

### Custom Antidote Install Location

Set `ANTIDOTE_HOME` **before** running `deploy.sh`:

```bash
export ANTIDOTE_HOME="$HOME/.local/share/antidote"
./deploy.sh
```

To make it permanent, add to `~/.zshenv` (sourced before `.zshrc`):

```bash
echo 'export ANTIDOTE_HOME="$HOME/.local/share/antidote"' >> ~/.zshenv
```

### Adding New Aliases

Edit `zsh/.zshrc` and add your aliases in the `# Aliases` section. Run `source ~/.zshrc` to apply.

## 5. Troubleshooting

### "zshrc: Antidote not set up"

Run `./deploy.sh` from the `zsh/` directory. This message means `~/.antidote/antidote.zsh` or `~/.zsh_plugins.txt` is missing.

### Plugins not loading after first launch

Antidote clones plugins on first load, which can take a few seconds. If plugins still don't load:

```bash
ls ~/.antidote/  # Should contain antidote.zsh and cloned plugin repos
```

If missing, re-run `./deploy.sh`.

### "insecure directory" warnings from compinit

Seen on macOS with Homebrew where `/opt/homebrew/share` may be group-writable. `.zshrc` already runs `compinit -i` to silence these safely. If warnings persist, check permissions:

```bash
compaudit
```

### History substring search keys don't work

The up/down arrow bindings for history substring search require the `zsh-users/zsh-history-substring-search` plugin to be loaded (via Antidote). Verify the plugin is listed in `~/.zsh_plugins.txt`.

### "command not found: mise"

Install mise:
```bash
curl https://mise.run | sh
```
Then restart your shell. `.zshrc` activates mise automatically once it's on PATH.

### rbenv / pyenv / n warnings on deploy

These are non-fatal warnings. The tools are optional — `.zshrc` skips their config blocks if they're not installed.
