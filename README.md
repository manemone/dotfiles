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
./deploy-all.sh --status                 # Show what's currently deployed (read-only)
./deploy-all.sh --rollback [id]          # Switch current back to the previous (or given) generation
./deploy-all.sh --dev                    # Point current at this working tree (live-edit mode)
```

Options can be combined:
```bash
./deploy-all.sh --dry-run --only tmux
./deploy-all.sh --force --only zsh,nvim --no-backup
```

`--status` / `--rollback` / `--dev` operate on the `current` symlink itself (see
[docs/adr/DOC-2608040229_deploy-distribution-method.md](docs/adr/DOC-2608040229_deploy-distribution-method.md))
and cannot be combined with each other or with `--only` / `--force` / `--backup` / `--no-backup` —
`--dry-run` is the only modifier they accept. `--status` has no side effects and is
safe to run against your real `$HOME`; `--rollback` and `--dev` actually repoint
`current`, so preview them with `--dry-run` first.

## Development Setup

If you're contributing to this repository (not just deploying it), enable the
pre-commit quality gate (shellcheck, shfmt, DOC-ID checks, a deploy dry-run).
The only tool this requires is [uv](https://docs.astral.sh/uv/):

```bash
uv tool install pre-commit
pre-commit install
```

From then on, `pre-commit run --all-files` runs most of the checks CI runs.
Deploy-related changes should additionally be verified with
`tests/deploy_smoke.sh`, which exercises `deploy-all.sh` against a sandboxed
`$HOME` (never your real one). See
[docs/design/DOC-2608020715-b_テスト方針.md](docs/design/DOC-2608020715-b_テスト方針.md)
for details. `bin/` changes should additionally be verified with
`python3 -m unittest discover -s bin/tests -v`; this is not part of
`pre-commit` (193 tests, ~40s) but runs on every PR via the `bin-tests` CI job.

## Directory Structure

```
~/.dotfiles/
├── AGENTS.md                  # Rules for AI agents developing this repo
├── CLAUDE.md                  # Entry point for Claude Code (imports AGENTS.md)
├── opencode.json              # Entry point for opencode (points to AGENTS.md + docs/design/)
├── .claude/
│   ├── pr-review.yml          # PR review workflow config (lint_cmd / test_cmd)
│   └── settings.json          # Permissions for AI agents in this repo (not the deployed claude/)
├── deploy-all.sh              # Unified deployment orchestrator
├── uninstall.sh               # Clean removal of known symlinks, restores backups where available
├── Brewfile                   # macOS Homebrew packages (zsh, tmux, git, curl)
├── apt-packages.txt           # Linux APT packages
├── .mise.toml                 # Runtime versions (python, node, ruby, rust, neovim, ripgrep, fd, lazygit)
├── .gitignore                 # Git ignore rules
├── LICENSE                    # MIT License
├── docs/                      # Design docs, ADRs, coding/PR conventions, umbrella-branch plans
│   ├── README.md              # Index: quick nav, DOC-ID registry, folder rules
│   ├── design/                # Active design docs (PR conventions, shell coding policy, test policy)
│   ├── adr/                   # Accepted architecture decision records (do not change once accepted)
│   ├── planning/              # Umbrella-branch plans and roadmaps (historical once merged)
│   └── reference/             # Operational references kept current (schemas, runbooks)
├── tools/                     # Repo-internal dev tools, not deployed to $HOME (unlike bin/)
│   └── doc-id/                # DOC-ID assign/check/verify CLI (Ruby stdlib only)
├── templates/                 # Copier templates distributed to OTHER repositories (independent of dotfiles itself)
│   └── repo-baseline/         # AGENTS.md/CLAUDE.md/opencode.json/pre-commit/DOC-ID/CI baseline; self-contained
├── shared/
│   └── helpers.sh             # Shared shell functions (logging, symlinks, platform detection)
├── bin/
│   ├── ocw                    # Git worktree manager with Herdr integration
│   ├── claude-ds              # Claude Code via DeepSeek API wrapper
│   ├── ocw-meter              # LLM cost / Claude quota observability (read-only, fail-open)
│   ├── tests/                 # Python unit tests for ocw-meter etc. (bin/tests/lint.sh + unittest suite)
│   ├── prices/                # Price tables used for cost calculation
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

## How deployment works

`$HOME` never links directly into this checkout. `./deploy-all.sh` copies the tool
directories into a dated **generation** directory under
`${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/generations/`, points a `current`
symlink at it, and every tool's `deploy.sh` links `$HOME` through `current` — never
through the generation directory directly. Re-running deploy creates a new
generation and swaps `current` over; the last few generations are kept (default 3,
override with `DOTFILES_KEEP_GENERATIONS`) so a broken deploy can be undone with
`--rollback` instead of git surgery. Editing this checkout after a deploy has no
effect on `$HOME` unless you're in dev mode (see below) — `$HOME` reads from the
generation snapshot, not the live working tree.

See
[docs/adr/DOC-2608040229_deploy-distribution-method.md](docs/adr/DOC-2608040229_deploy-distribution-method.md)
for the full rationale, and
[docs/reference/DOC-2608040805_配布実体運用ガイド.md](docs/reference/DOC-2608040805_配布実体運用ガイド.md)
for day-to-day operations (inspecting what's deployed, rolling back, entering/leaving
dev mode, recovering a broken symlink, migrating an older machine).

## Working on this checkout: dev mode and worktrees

Because `$HOME` normally reads from a copied generation, edits to this checkout
(including in a linked `git worktree` created by `git worktree add` or `ocw`) do
**not** reach `$HOME` until you re-deploy. If you want live-edit behavior instead —
useful while iterating on a config change — use dev mode:

```bash
./deploy-all.sh --dev
```

This points `current` directly at this working tree (no generation is created), so
edits take effect immediately, matching how earlier versions of this repo always
behaved. The tradeoff dev mode brings back: if `current` points at a **linked**
worktree and that worktree is removed (`ocw rm`, `git worktree remove`), every
`$HOME` symlink breaks the moment it disappears. `--dev` warns when this applies:

```
[WARN] This working tree is a linked git worktree:
[WARN]   /path/to/dotfiles/my-feature
[WARN] Dev mode makes $HOME resolve directly into it via current. Removing this
[WARN] worktree (e.g. 'ocw rm') will break every $HOME symlink until you switch
[WARN] back to generation mode.
```

A related but separate warning can show up during an ordinary (non-`--dev`) deploy
too: running `./deploy-all.sh` itself from a linked worktree still prints the
"Deploying from a linked git worktree" warning below, left over from the pre-generation
direct-link scheme. In generation mode this warning is misleading — the
generation this deploy creates is a `cp -a` snapshot, so `$HOME` symlinks resolve
through it rather than through the worktree, and removing the worktree afterward
does **not** break them. Only dev mode actually makes the worktree's removal
break `$HOME` symlinks, as described above.

```
[WARN] Deploying from a linked git worktree:
[WARN]   /path/to/dotfiles/my-feature
[WARN] Symlinks will point INTO this worktree and will break when it is
[WARN] removed (e.g. by 'ocw rm').
```

Re-run `./deploy-all.sh` (without `--dev`) to leave dev mode and go back to the
default, safer generation mode — this also fixes any symlinks a removed dev-mode
worktree left broken. Set `DOTFILES_QUIET_WORKTREE_WARNING=1` to silence the
warning. To check what's currently deployed (generation vs. dev mode, and whether
any `$HOME` symlink is broken) without side effects:

```bash
./deploy-all.sh --status
```

## Uninstalling

```bash
./uninstall.sh               # Interactive — asks before each tool
./uninstall.sh --force       # Skip confirmations
./uninstall.sh --dry-run     # Preview without changes
./uninstall.sh --only tmux   # Uninstall a specific tool
```

The uninstall script removes **known symlinks**, restores backed-up config files
(`*.backup`), and — once no remaining tool still references it — cleans up the
distribution artifacts themselves (the `generations/` directory, the scratch `.tmp/`
directory, the `current` symlink, and the canonical prefix itself once empty). If
`current` is in dev mode (pointing at a working tree), `generations/` / `.tmp/` /
`current` are still cleaned up as usual; only the working tree `current` points at
is protected and never touched.
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
