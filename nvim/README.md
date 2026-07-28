# NeoVim Configuration (lazy.nvim)

## Design Philosophy

**Built-in first. mini.nvim second. lazy.nvim is just glue.**

| Layer | Role |
|---|---|
| NeoVim built-in | First choice — `vim.comment`, LSP, `vim.diagnostic`, `vim.lsp.buf.*` |
| mini.nvim | Small features — surround, pairs, ai text-objects (no lazy-loading needed) |
| lazy.nvim | Plugin management only — lazy-loading + lockfile |

### What We Removed (and Why)

| Old Plugin | Replacement | Reason |
|---|---|---|
| `dein.vim` | `lazy.nvim` | Modern, faster, Lua-native |
| `coc.nvim` | `nvim-lspconfig` + `mason.nvim` | Built-in LSP is sufficient |
| `neosnippet` | `LuaSnip` | Lua-native, VS Code snippet compat |
| `nerdcommenter` | `vim.comment` (built-in) | NeoVim 0.10+ has `gc` operator |
| `vim-surround` | `mini.surround` | Same UX, lighter, Lua-native |
| `lexima.vim` | `mini.pairs` | Auto-pairs without Vimscript |
| `vim-easy-align` | `=`, `gw`, `gq` (built-in) | Built-in formatting operators cover most cases |
| `vim-airline` | `lualine.nvim` | Lua-native, faster, simpler config |
| `vim-gitgutter` | `gitsigns.nvim` | More features, Lua-native |
| `denite.nvim` | `telescope.nvim` | Modern, extensible, Lua-native |
| `vim-expand-region` | `treesitter-textobjects` | Semantic text objects are superior |
| `molokai` | `dracula.nvim` | Modern, maintained, better tree-sitter support |
| `vim-coffee-script` | — | CoffeeScript is dead |
| `vim-vue` | `treesitter` + `volar` LSP | Better Vue support |
| `vim-rails` | — | Generic dotfiles don't need Rails specifics |
| `typescript-vim` | `treesitter` | Treesitter handles syntax |
| `context_filetype.vim` | — | LuaSnip doesn't need it |
| `neosnippet-snippets` | `friendly-snippets` | VS Code-compatible snippet collection |

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| **NeoVim ≥ 0.10** | Required (LSP, commenting, etc.) | `mise use neovim` or [neovim.io](https://neovim.io) |
| **mise** | Runtime manager for Python, Node, etc. | `curl https://mise.run \| sh` |
| **Node.js LTS** | LSP servers (ts_ls, volar, etc.) | `mise use node@lts` |
| **ripgrep** (`rg`) | Telescope `live_grep` | `brew install ripgrep` / `apt install ripgrep` |
| **fd** | Telescope `find_files` (optional) | `brew install fd` / `apt install fd-find` |
| **git** | Plugin management, fugitive | Built-in on most systems |
| **python3** | Python LSP, provider | `mise use python@latest` |

## Quick Start

```bash
# 1. Run deploy script
cd nvim
source deploy.sh

# 2. Open NeoVim (plugins auto-install on first launch)
nvim

# 3. LSP servers auto-install via mason.nvim.
#    To add more, run inside NeoVim:
#    :Mason
```

After first launch:
- `:checkhealth` — verify everything works
- `:Lazy` — manage plugins
- `:Mason` — manage LSP servers / formatters / linters
- `:Lazy lock` — update lockfile after plugin updates
- `:TSUpdate` — update tree-sitter parsers

## Directory Structure

```
nvim/
├── init.lua                  # Entry point — lazy.nvim bootstrap
├── lazy-lock.json            # Plugin version lockfile
├── deploy.sh                 # Deployment script
├── README.md                 # This file
└── lua/
    ├── config/
    │   ├── options.lua       # vim.opt settings
    │   ├── keymaps.lua       # Key mappings
    │   └── autocmds.lua      # Autocommands
    └── plugins/
        ├── dracula.lua       # Colorscheme
        ├── telescope.lua     # Fuzzy finder
        ├── treesitter.lua    # Syntax highlighting
        ├── lsp.lua           # LSP + Mason
        ├── luasnip.lua       # Snippets
        ├── gitsigns.lua      # Git signs
        ├── lualine.lua       # Statusline
        ├── mini.lua          # mini.surround, mini.pairs, mini.ai
        ├── which-key.lua     # Keymap helper
        └── fugitive.lua      # Git commands
```

## LSP Setup

LSP servers are managed by **mason.nvim** and auto-installed on first launch:

| Language | Server |
|---|---|
| Lua | `lua_ls` |
| Rust | `rust_analyzer` |
| TypeScript / JS | `ts_ls` |
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

Add more via `:Mason` or edit `lua/plugins/lsp.lua`.

## Key Mappings

| Key | Action |
|---|---|
| `<Space>` | Leader key |
| `<Leader>ff` | Find files (Telescope) |
| `<Leader>fg` | Live grep (Telescope) |
| `<Leader>fb` / `<Leader>d` | Buffers |
| `<Leader>fh` | Help tags |
| `<Leader>fd` | Diagnostics |
| `<Leader>fs` | Document symbols |
| `<Leader>w` | Save |
| `<Leader>/` | Toggle comment (built-in `gc`) |
| `<Leader>rn` | Rename (LSP) |
| `<Leader>ca` | Code action (LSP) |
| `<Leader>f` | Format (LSP) |
| `gd` | Go to definition |
| `gr` | Go to references |
| `K` | Hover |
| `[d` / `]d` | Previous / next diagnostic |
| `<Leader>hs` | Stage hunk (git) |
| `<Leader>hr` | Reset hunk (git) |
| `<Leader>gs` | Git status |
| `<C-h/j/k/l>` | Window navigation |
| `<A-;>` | Exit terminal mode |

Full keymaps in `lua/config/keymaps.lua`. Press `<Space>` and wait for which-key popup.
