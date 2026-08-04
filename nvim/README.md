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
| **curl** | any | Mason LSP downloads; blink.cmp's prebuilt fuzzy-matcher binary (first launch only) | Built-in on most systems |
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
| Completion | `saghen/blink.cmp` | Auto-popup completion (lsp/path/snippets/buffer sources) |
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
        ├── blink.lua          # Completion popup (Tab/S-Tab snippet nav, LuaSnip integration)
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
| `<Leader>n` | n | Rename current file (filesystem rename; refuses to overwrite an existing file) |
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
| `<C-n>` / `<C-p>` (or `<Down>`/`<Up>`) | i | Next/prev completion item (blink.cmp) |
| `<C-y>` | i | Accept completion item (blink.cmp) |
| `<C-space>` | i | Trigger/toggle completion menu (blink.cmp) |
| `<C-e>` | i | Cancel completion menu (blink.cmp) |
| `<C-b>` / `<C-f>` | i | Scroll completion documentation (blink.cmp) |
| `<Tab>` / `<S-Tab>` | i, s | Move to next/prev snippet placeholder, else a literal Tab (blink.cmp) |
| `<C-k>` | i, s | Expand snippet at cursor (LuaSnip) |

Full keymaps in `lua/config/keymaps.lua`, `lua/plugins/lsp.lua`, and `lua/plugins/blink.lua`.
Press `<Space>` and wait for which-key popup to discover available shortcuts.

## 4. Customization

### Adding Plugins

1. Create a new file in `nvim/lua/plugins/` (e.g., `my-plugin.lua`)
2. Add your plugin spec (see existing files for patterns)
3. Run `nvim` — lazy.nvim installs missing plugins automatically
4. Run `:Lazy lock` to update the lockfile
5. Adopt the updated lockfile into the repo — see "Updating the plugin lockfile" below

### Updating the plugin lockfile

`~/.config/nvim/lazy-lock.json` is a symlink into the distribution artifact (`current`), not into
this repo's working tree (see the top-level `AGENTS.md`'s "デプロイの仕組み" and ADR
DOC-2608040229). When lazy.nvim writes to it — via `:Lazy update`, `:Lazy sync`, or `:Lazy lock` —
the write lands in the currently-deployed *generation*, not in `nvim/lazy-lock.json` in this repo.
It won't show up in `git status`, and it will be silently lost the next time `./deploy-all.sh`
builds a new generation (a new generation is always copied from the source tree, not from the
outgoing generation).

`./deploy-all.sh` detects this before it can happen: if the currently-deployed generation's
`lazy-lock.json` differs from this repo's, a plain deploy refuses to proceed and tells you to run:

```bash
./deploy-all.sh --adopt-state
```

This copies the updated `lazy-lock.json` (and any other state file writeback) back into this
source tree — nothing else changes (no new generation, no `$HOME` symlink touched). Review the
diff, commit it, then run `./deploy-all.sh` normally to deploy it. `./deploy-all.sh --status` also
reports any not-yet-adopted lockfile changes if you want to check without triggering the refusal.

### Adding LSP Servers

```bash
# From within NeoVim:
:Mason              # Browse and install servers

# Or edit lua/plugins/lsp.lua and add to the `ensure_installed` list
```

### Changing Keybindings

Edit `nvim/lua/config/keymaps.lua` or the relevant plugin file. Telescope keymaps are in `lua/plugins/telescope.lua`, LSP keymaps are in `lua/plugins/lsp.lua`, completion keymaps are in `lua/plugins/blink.lua`.

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

### Completion menu not showing suggestions / fuzzy matching feels off

blink.cmp downloads a prebuilt Rust fuzzy-matcher binary via `curl` on its first load. If that
download fails (no network access, blocked `curl`), it falls back to a pure-Lua matcher with a
one-time warning — completion still works, just slower to filter large candidate lists. To silence
the warning and stick with the Lua matcher intentionally, set in `lua/plugins/blink.lua`:
```lua
opts = {
  fuzzy = { implementation = "lua" },
  -- ...
}
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
