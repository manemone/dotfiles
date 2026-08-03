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

On a fresh machine, run the top-level `deploy-all.sh` (not `zsh/deploy.sh` directly) —
`$HOME` links through a distribution artifact under `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/`
that only `deploy-all.sh` creates. Running `zsh/deploy.sh` standalone before that
exists fails with an error pointing you back here.

```bash
cd ~/.dotfiles
./deploy-all.sh --only zsh
exec zsh
```

Once `deploy-all.sh` has run at least once, you can re-run `zsh/deploy.sh` directly
to re-link `zsh` alone (it reuses the existing distribution artifact rather than
creating a new one).

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

### PATH Additions (auto-detected)

Each entry is added only when the directory exists, so machines without a given
tool are unaffected. These are prepended **after** the version managers, so
hand-written scripts take precedence over shims.

| Directory | Contents |
|---|---|
| `$HOME/bin` | Personal scripts |
| `$HOME/.local/bin` | User-local executables (`pip --user`, manual symlinks) |
| `$HOME/go/bin` | Go binaries (also sets `GOPATH`) |
| `$HOME/.opencode/bin` | opencode CLI |
| `$HOME/.cargo/bin` | Rust toolchain |

### History

- File: `~/.zsh_history`
- Size: 10,000 entries
- Options: `SHARE_HISTORY`, `HIST_IGNORE_DUPS`, `HIST_IGNORE_SPACE`, `HIST_VERIFY`

## 4. Customization

### Machine-Local Settings (`~/.zshrc.local`)

`.zshrc` sources `~/.zshrc.local` as its **last** step, if the file exists. This
file is deliberately **not** tracked in this repository.

Use it for anything that belongs to one machine only:

- Host addresses that differ per machine (VM IPs, WSL host routes)
- API keys and tokens — keeping them here means they never reach the shared
  repository or its history
- Work-only paths, proxies, or company-internal endpoints
- One-off overrides of anything set in `.zshrc`

```bash
cat >> ~/.zshrc.local <<'EOF'
export SOME_SERVICE_TOKEN="..."
export PATH="$HOME/work-tools/bin:$PATH"
EOF

source ~/.zshrc
```

Because it is sourced last, it can override any variable, alias, or PATH entry
set earlier. Anything that should apply to *every* machine belongs in
`zsh/.zshrc` instead, guarded by an existence check.

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

### "command not found" after switching from bash

`~/.bashrc` is not read by zsh, so any PATH entry or export that lived only
there is gone once zsh becomes the login shell. Compare the two in a clean
environment — without `env -i` the child shell inherits the parent's exports and
everything looks fine even when it isn't:

```bash
env -i HOME="$HOME" TERM=xterm USER="$USER" zsh -l -i -c 'echo $PATH' | tr ':' '\n'
```

Then decide where each missing entry belongs:

- Useful on every machine → add to `zsh/.zshrc` with an existence guard
- Specific to this machine → add to `~/.zshrc.local`
