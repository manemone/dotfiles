# NeoVim Configuration (lazy.nvim)

## Design Philosophy

**Built-in first. mini.nvim second. lazy.nvim is just glue.**

| Layer | Role |
|---|---|
| NeoVim built-in | First choice — `vim.comment`, LSP, `vim.diagnostic`, `vim.lsp.buf.*` |
| mini.nvim | Small features — surround, pairs, ai text-objects (no lazy-loading needed) |
| lazy.nvim | Plugin management only — lazy-loading + lockfile |

## 1. Requirements

| Tool | Minimum Version | Why | Install |
|---|---|---|---|
| **NeoVim** | ≥ 0.10 | LSP, built-in commenting (`gc`), Lua APIs | `mise use neovim` or [neovim.io](https://neovim.io) |
| **Git** | any | Plugin management (lazy.nvim clones repos) | Built-in on most systems |
| **curl** | any | Mason LSP downloads | Built-in on most systems |
| **Node.js** | LTS | LSP servers (ts_ls, volar, jsonls, yamlls, bashls) | `mise use node@lts` |
| **Python 3** | 3.8+ | Python LSP (pyright), Neovim Python provider | `mise use python@latest` |
| **ripgrep** (`rg`) | any | Telescope `live_grep` | `mise use ripgrep` |
| **fd** | any (recommended) | Telescope `find_files` (falls back to `find`) | `mise use fd` |

### Install Tools by Platform

**macOS**
```bash
brew install ripgrep fd node python3
# or use mise:
mise use ripgrep fd node@lts python@latest
```

**Linux (Ubuntu/Debian)**
```bash
sudo apt install ripgrep fd-find nodejs python3
# or use mise:
mise use ripgrep fd node@lts python@latest
```

**WSL2**
```bash
sudo apt install ripgrep fd-find nodejs python3
# or use mise:
mise use ripgrep fd node@lts python@latest
```

## 2. Quick Start

On a fresh machine, run the top-level `deploy-all.sh` (not `nvim/deploy.sh` directly) —
`$HOME` links through a distribution artifact under `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/`
that only `deploy-all.sh` creates. Running `nvim/deploy.sh` standalone before that
exists fails with an error pointing you back here.

```bash
# 1. Run the top-level deploy script
cd ~/.dotfiles
./deploy-all.sh --only nvim

# 2. Open NeoVim — plugins auto-install via lazy.nvim on first launch
nvim
```

Once `deploy-all.sh` has run at least once, you can re-run `nvim/deploy.sh` directly
to re-link `nvim` alone (it reuses the existing distribution artifact rather than
creating a new one).

The deploy script:
- Creates `~/.config/nvim/` directory
- Symlinks `init.lua`, `lua/`, and `lazy-lock.json` into `~/.config/nvim/`
- Installs lazy.nvim to `~/.local/share/nvim/lazy/lazy.nvim`
- Installs `pynvim` (Python 3 provider) via mise-managed Python or system pip
- Installs `neovim` Ruby gem if Ruby is available
- Cleans up old dein.vim symlinks (`dein.toml`, `dein_lazy.toml`, `init.vim`)
- Warns if optional tools (ripgrep, fd, node, mise) are missing

After first launch:
| Command | Purpose |
|---|---|
| `:checkhealth` | Verify everything works |
| `:Lazy` | Manage plugins (install, update, sync) |
| `:Mason` | Manage LSP servers, formatters, linters |
| `:Lazy lock` | Update lockfile after plugin changes |
| `:TSUpdate` | Update tree-sitter parsers |

## 3. What's Included

### Plugin List

| Category | Plugin | Purpose |
|---|---|---|
| Colorscheme | `dracula/dracula.nvim` | Dark theme with tree-sitter support |
| Fuzzy finder | `nvim-telescope/telescope.nvim` | File search, grep, buffers, help tags, diagnostics |
| Syntax | `nvim-treesitter/nvim-treesitter` | AST-based highlighting, text objects |
| LSP | `neovim/nvim-lspconfig` | LSP client configuration |
| LSP installer | `williamboman/mason.nvim` | LSP server / formatter / linter management |
| Snippets | `L3MON4D3/LuaSnip` | Lua-native snippet engine |
| Snippet collection | `rafamadriz/friendly-snippets` | VS Code-compatible snippet library |
| Git signs | `lewis6991/gitsigns.nvim` | Gutter indicators for changed lines |
| Statusline | `nvim-lualine/lualine.nvim` | Fast, Lua-native statusline |
| Mini utilities | `echasnovski/mini.nvim` | surround, pairs, ai text-objects |
| Keymap helper | `folke/which-key.nvim` | Popup showing available keybindings |
| Git commands | `tpope/vim-fugitive` | `:Git`, `:Gblame`, `:Gdiff` |

### LSP Servers (auto-installed via mason.nvim)

| Language | Server |
|---|---|
| Lua | `lua_ls` |
| Rust | `rust_analyzer` |
| TypeScript / JavaScript | `ts_ls` |
| Vue | `volar` |
| Python | `pyright` |
| Go | `gopls` |
| Ruby | `ruby_lsp` |
| JSON | `jsonls` |
| YAML | `yamlls` |
| TOML | `taplo` |
| Bash | `bashls` |
| Zig | `zls` |
| Markdown | `marksman` |

### Directory Structure

```
~/.config/nvim/                (deployed via symlinks)
├── init.lua                   # Entry point — leader key, python3 provider, lazy.nvim bootstrap
├── lazy-lock.json             # Plugin version lockfile
└── lua/
    ├── config/
    │   ├── options.lua        # vim.opt settings (line numbers, tabs, folding, etc.)
    │   ├── keymaps.lua        # Key mappings (window nav, clipboard, commenting, terminal)
    │   └── autocmds.lua       # Autocommands
    └── plugins/
        ├── dracula.lua        # Colorscheme
        ├── telescope.lua      # Fuzzy finder (ff, fg, fb, fh, fd, fs keymaps)
        ├── treesitter.lua     # Syntax highlighting + text objects
        ├── lsp.lua            # LSP config + Mason + on_attach keymaps (gd, gr, K, rn, ca)
        ├── luasnip.lua        # Snippet engine
        ├── gitsigns.lua       # Git gutter (hs, hr, gs keymaps)
        ├── lualine.lua        # Statusline
        ├── mini.lua           # mini.surround, mini.pairs, mini.ai
        ├── which-key.lua      # Keymap popup helper
        └── fugitive.lua       # Git commands
```

### Keybindings Reference

| Key | Mode | Action |
|---|---|---|
| `<Space>` | n | Leader key |
| `<Leader>ff` | n | Find files (Telescope) |
| `<Leader>fg` | n | Live grep (Telescope) |
| `<Leader>fb` | n | Browse buffers (Telescope) |
| `<Leader>fh` | n | Help tags (Telescope) |
| `<Leader>fd` | n | Diagnostics (Telescope) |
| `<Leader>fs` | n | Document symbols (Telescope) |
| `<Leader>w` | n | Save buffer |
| `<Leader>/` | n, v | Toggle comment (built-in `gcc` / `gc`) |
| `<Leader>y` | v | Yank to system clipboard |
| `<Leader>p` | n, v | Paste from system clipboard |
| `<Leader>rn` | n | Rename symbol (LSP) |
| `<Leader>ca` | n, v | Code action (LSP) |
| `<Leader>f` | n | Format (LSP) |
| `gd` | n | Go to definition |
| `gr` | n | Go to references |
| `K` | n | Hover (LSP) |
| `[d` / `]d` | n | Previous / next diagnostic |
| `<C-h/j/k/l>` | n | Window navigation |
| `<A-;>` / `<Esc>` | t | Exit terminal mode |

Full keymaps in `lua/config/keymaps.lua` and `lua/plugins/lsp.lua`.
Press `<Space>` and wait for which-key popup to discover available shortcuts.

## 4. Customization

### Adding Plugins

1. Create a new file in `nvim/lua/plugins/` (e.g., `my-plugin.lua`)
2. Add your plugin spec (see existing files for patterns)
3. Run `nvim` — lazy.nvim installs missing plugins automatically
4. Run `:Lazy lock` to update the lockfile

### Adding LSP Servers

```bash
# From within NeoVim:
:Mason              # Browse and install servers

# Or edit lua/plugins/lsp.lua and add to the `ensure_installed` list
```

### Changing Keybindings

Edit `nvim/lua/config/keymaps.lua` or the relevant plugin file. Telescope keymaps are in `lua/plugins/telescope.lua`, LSP keymaps are in `lua/plugins/lsp.lua`.

### Changing Colorscheme

1. Replace `dracula/dracula.nvim` with your preferred colorscheme in a plugin file
2. Update `install.colorscheme` in `init.lua`
3. Run `:Lazy sync`

## 5. Troubleshooting

### Plugins not installing on first launch

```bash
# Check lazy.nvim is cloned:
ls ~/.local/share/nvim/lazy/lazy.nvim

# If missing, the bootstrap in init.lua handles it — just re-open nvim.
# Or install manually:
git clone --filter=blob:none --branch=stable \
  https://github.com/folke/lazy.nvim.git \
  ~/.local/share/nvim/lazy/lazy.nvim
```

### LSP server not starting

Check Mason installed it:
```vim
:Mason
```

Check LSP is attached to the buffer:
```vim
:LspInfo
```

Common fixes:
- Ensure the language's runtime is installed (Node.js for ts_ls, Python for pyright)
- Run `:MasonInstall <server-name>` to reinstall
- Run `:checkhealth lsp` for diagnostics

### Python provider warning

`init.lua` auto-detects Python 3 via mise or system `python3`. If you see "Python 3 provider not found":
```bash
mise use python@latest
pip install pynvim
```

### Telescope live_grep shows no results

Ensure `ripgrep` is installed:
```bash
which rg
# If missing:
mise use ripgrep
# or macOS: brew install ripgrep
# or Linux: sudo apt install ripgrep
```

### Old dein.vim plugins still loading

The deploy script backs up old configs (`.migrated-to-lazy` suffix) and removes symlinks. If old plugins persist, check for leftover files:
```bash
ls ~/.config/nvim/*.toml ~/.config/nvim/init.vim 2>/dev/null
```
Delete or move them manually if found.

### "No specs found for module plugins.X"

This means lazy.nvim can't find a plugin file. Ensure `nvim/lua/plugins/` is symlinked correctly:
```bash
readlink ~/.config/nvim/lua
# Should point through the distribution's `current` symlink, e.g.
# ~/.local/share/dotfiles/current/nvim/lua (not directly into ~/.dotfiles).
# Run ./deploy-all.sh --status from the repo root to see what `current` resolves to.
```
