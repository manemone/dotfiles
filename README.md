# dotfiles

Easily deployable, cross-platform dotfiles managed with [mise](https://mise.jdx.dev).

## Supported Tools

| Tool | Description | Plugin Manager |
|---|---|---|
| **Zsh** | Shell | [Antidote](https://github.com/mattmc3/antidote) |
| **NeoVim** | Editor | [lazy.nvim](https://github.com/folke/lazy.nvim) |
| **tmux** | Terminal multiplexer | — (built-in) |
| **bin** | Custom CLI tools (ocw, claude-ds) | — (standalone scripts) |
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
├── AGENTS.md                  # Rules for AI agents developing this repo
├── CLAUDE.md                  # Entry point for Claude Code (imports AGENTS.md)
├── deploy-all.sh              # Unified deployment orchestrator
├── uninstall.sh               # Clean removal of known symlinks, restores backups where available
├── Brewfile                   # macOS Homebrew packages (zsh, tmux, git, curl)
├── apt-packages.txt           # Linux APT packages
├── .mise.toml                 # Runtime versions (python, node, ruby, rust, neovim, ripgrep, fd, lazygit)
├── .gitignore                 # Git ignore rules
├── LICENSE                    # MIT License
├── docs/                      # Design docs, coding/PR conventions, umbrella-branch plans
│   ├── README.md              # Index: quick nav, DOC-ID registry, folder rules
│   ├── design/                # Active design docs (PR conventions, shell coding policy, test policy)
│   └── planning/              # Umbrella-branch plans and roadmaps
├── tools/                     # Repo-internal dev tools, not deployed to $HOME (unlike bin/)
│   └── doc-id/                # DOC-ID assign/check/verify CLI (Ruby stdlib only)
├── shared/
│   └── helpers.sh             # Shared shell functions (logging, symlinks, platform detection)
├── bin/
│   ├── ocw                    # Git worktree manager with Herdr integration
│   ├── claude-ds              # Claude Code via DeepSeek API wrapper
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

- [bin/README.md](bin/README.md) — CLI tools (ocw worktree manager, claude-ds DeepSeek wrapper)
- [claude/README.md](claude/README.md) — Claude Code config, skills, machine-specific customization
- [zsh/README.md](zsh/README.md) — shell setup, plugin management, aliases, version managers
- [nvim/README.md](nvim/README.md) — editor setup, LSP servers, keybindings, plugins
- [tmux/README.md](tmux/README.md) — multiplexer setup, Vim-style keybindings, clipboard
