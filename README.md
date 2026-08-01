# dotfiles

Easily deployable, cross-platform dotfiles managed with [mise](https://mise.jdx.dev).

## Supported Tools

| Tool | Description | Plugin Manager |
|---|---|---|
| **Zsh** | Shell | [Antidote](https://github.com/mattmc3/antidote) |
| **NeoVim** | Editor | [lazy.nvim](https://github.com/folke/lazy.nvim) |
| **tmux** | Terminal multiplexer | — (built-in) |
| **bin** | Custom CLI tools (ocw, claude-ds, ocw-meter) | — (standalone scripts) |
| **claude** | Claude Code config & skills | — (built-in) |

## Supported Platforms

- **macOS** — Apple Silicon (arm64) and Intel (x86_64)
- **Linux** — Ubuntu / Debian
- **WSL2** — Windows Subsystem for Linux 2

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| **git** | Clone the repo, plugin management | Built-in on most systems |
| **curl** | Bootstrap scripts | Built-in on most systems |
| **mise** | Runtime version manager (NeoVim, Python, Node.js, Ruby, Rust, ripgrep, fd, lazygit) | `curl https://mise.run \| sh` |

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/manemone/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 2. Install managed runtimes
mise trust
mise install

# 3. Install platform-specific system packages
# macOS:
brew bundle --file Brewfile

# Linux / WSL:
sudo apt update && sudo apt install $(cat apt-packages.txt)

# 4. Deploy all dotfiles
./deploy-all.sh
```

### deploy-all.sh Options

```bash
./deploy-all.sh                          # Interactive mode — asks before each tool
./deploy-all.sh --dry-run                # Preview what would be done (no changes)
./deploy-all.sh --force                  # Skip all confirmation prompts
./deploy-all.sh --only zsh,nvim          # Deploy specific tools (comma-separated)
./deploy-all.sh --backup                 # Back up existing config files (default)
./deploy-all.sh --no-backup              # Overwrite without backing up
```

Options can be combined:
```bash
./deploy-all.sh --dry-run --only tmux
./deploy-all.sh --force --only zsh,nvim --no-backup
```

## Directory Structure

```
~/.dotfiles/
├── deploy-all.sh              # Unified deployment orchestrator
├── uninstall.sh               # Clean removal of known symlinks, restores backups where available
├── Brewfile                   # macOS Homebrew packages (zsh, tmux, git, curl)
├── apt-packages.txt           # Linux APT packages
├── .mise.toml                 # Runtime versions (python, node, ruby, rust, neovim, ripgrep, fd, lazygit)
├── .gitignore                 # Git ignore rules
├── LICENSE                    # MIT License
├── docs/                      # Documentation (see docs/README.md for the full index)
│   ├── README.md              # Index: quick-nav + full DOC-ID list. Only file allowed directly under docs/
│   ├── adr/                   # Accepted architecture decision records
│   ├── planning/               # Umbrella-branch plans and roadmaps (historical once merged)
│   └── reference/              # Operational references kept current (schemas, runbooks)
├── shared/
│   └── helpers.sh             # Shared shell functions (logging, symlinks, platform detection)
├── bin/
│   ├── ocw                    # Git worktree manager with Herdr integration
│   ├── claude-ds              # Claude Code via DeepSeek API wrapper
│   ├── ocw-meter               # LLM cost / Claude quota observability (read-only, fail-open)
│   ├── deploy.sh              # bin deployment script
│   └── README.md
├── claude/
│   ├── CLAUDE.md              # Claude Code global personal instructions
│   ├── settings.json          # Claude Code base settings (no machine-specific config)
│   ├── settings.machine.json.example  # Template for machine-specific overrides
│   ├── deploy.sh              # claude deployment script
│   ├── skills/                # Claude Code custom skills (auto-detected)
│   └── README.md
├── zsh/
│   ├── .zshrc                 # Shell configuration
│   ├── .zsh_plugins.txt       # Antidote plugin declarations
│   ├── deploy.sh              # Zsh deployment script
│   └── README.md
├── nvim/
│   ├── init.lua               # NeoVim entry point (lazy.nvim bootstrap)
│   ├── lazy-lock.json         # Plugin version lockfile
│   ├── deploy.sh              # NeoVim deployment script
│   ├── lua/
│   │   ├── config/            # Core settings (options, keymaps, autocmds)
│   │   └── plugins/           # Plugin specs (lsp, telescope, treesitter, etc.)
│   └── README.md
└── tmux/
    ├── tmux.conf              # tmux configuration
    ├── deploy.sh              # tmux deployment script
    └── README.md
```

## Deploying from a git worktree

Deploy scripts symlink files **from this checkout** into `$HOME`. If you deploy
from a linked git worktree (created by `git worktree add`, or by `ocw`), those
symlinks point into that worktree — and they break silently the moment the
worktree is removed (`ocw rm`, `git worktree remove`). `~/.zshrc`,
`~/.claude/skills/*` and `~/bin/*` all stop working, long after the deploy
reported success.

The deploy scripts warn when this happens:

```
[WARN] Deploying from a linked git worktree:
[WARN]   /path/to/dotfiles/my-feature
[WARN] Symlinks will point INTO this worktree and will break when it is
[WARN] removed (e.g. by 'ocw rm').
[WARN] After merging, re-run the deploy from the main worktree:
[WARN]   cd /path/to/dotfiles/master && ./deploy-all.sh
```

Deploying from a worktree is fine while testing a change. Just **re-run the
deploy from the main worktree once the change is merged**, before removing the
worktree. Set `DOTFILES_QUIET_WORKTREE_WARNING=1` to silence the warning.

If symlinks are already broken, list the dangling ones with:

```bash
find ~ ~/.config ~/.claude ~/.claude/skills ~/bin -maxdepth 1 -type l ! -exec test -e {} \; -print
```

then re-run `./deploy-all.sh` from the main worktree.

## Uninstalling

```bash
./uninstall.sh               # Interactive — asks before each tool
./uninstall.sh --force       # Skip confirmations
./uninstall.sh --dry-run     # Preview without changes
./uninstall.sh --only tmux   # Uninstall a specific tool
```

The uninstall script removes **known symlinks** and restores backed-up config files (`*.backup`).
Note: `--only nvim` currently removes legacy dein.vim symlinks; lazy.nvim symlinks (`init.lua`, `lua/`, `lazy-lock.json`) are not yet tracked.
See each tool's deploy script for the full list of files it creates.

## Next Steps

See each tool's README for detailed configuration and troubleshooting:

- [bin/README.md](bin/README.md) — CLI tools (ocw worktree manager, claude-ds DeepSeek wrapper, ocw-meter observability)
- [claude/README.md](claude/README.md) — Claude Code config, skills, machine-specific customization
- [zsh/README.md](zsh/README.md) — shell setup, plugin management, aliases, version managers
- [nvim/README.md](nvim/README.md) — editor setup, LSP servers, keybindings, plugins
- [tmux/README.md](tmux/README.md) — multiplexer setup, Vim-style keybindings, clipboard
- [docs/README.md](docs/README.md) — documentation index (ADRs, umbrella-branch plans, operational references)
