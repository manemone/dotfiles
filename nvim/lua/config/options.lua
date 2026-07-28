-- options.lua — vim.opt settings (translated from init.vim)
-- Prefer NeoVim built-in capabilities over plugins.

local opt = vim.opt

-- ── Appearance ─────────────────────────────────────────────────────────

opt.termguicolors = true         -- 24-bit color (required by modern colorschemes)
opt.number = true                -- show line numbers
opt.relativenumber = true        -- relative line numbers (modern convenience)
opt.signcolumn = "yes"           -- always show sign column (LSP/gitsigns gutter)
opt.cursorline = true            -- highlight current line
opt.showmatch = true             -- briefly jump to matching bracket
opt.matchtime = 1                -- tenths of a second for showmatch
opt.inccommand = "split"         -- live preview of :s substitutions
opt.laststatus = 3               -- global statusline (1 line for all windows)
opt.showmode = false             -- mode is shown in statusline (lualine)
opt.pumheight = 10               -- popup menu max height

-- ── Indentation ────────────────────────────────────────────────────────

opt.tabstop = 2                  -- display width of a <Tab> character
opt.softtabstop = 2              -- <Tab> / <BS> inserts/deletes this many spaces
opt.shiftwidth = 2               -- >> / << / autoindent width
opt.autoindent = true            -- copy indent from current line on <CR>
opt.expandtab = true             -- <Tab> inserts spaces, never literal tabs
opt.shiftround = true            -- >> / << round indent to multiple of shiftwidth
opt.smartindent = true           -- extra indent in C-like contexts

-- ── Search ─────────────────────────────────────────────────────────────

opt.incsearch = true             -- highlight matches as you type
opt.hlsearch = true              -- keep matches highlighted after search
opt.ignorecase = true            -- case-insensitive search by default
opt.smartcase = true             -- case-sensitive when uppercase in pattern
opt.wrapscan = true              -- wrap around EOF when searching

-- ── Clipboard ──────────────────────────────────────────────────────────

opt.clipboard = "unnamedplus"    -- yank/paste to/from system clipboard (+ register)

-- ── Splits ─────────────────────────────────────────────────────────────

opt.splitbelow = true            -- :split opens below current window
opt.splitright = true            -- :vsplit opens right of current window

-- ── Scrolling ──────────────────────────────────────────────────────────

opt.scrolloff = 4                -- keep 4 lines visible above/below cursor
opt.sidescrolloff = 8            -- keep 8 columns visible left/right of cursor

-- ── Misc ───────────────────────────────────────────────────────────────

opt.mouse = "a"                  -- enable mouse in all modes
opt.backup = false               -- no backup files
opt.swapfile = false             -- no swap files (use undo history instead)
opt.undofile = true              -- persistent undo
opt.undodir = vim.fn.stdpath("data") .. "/undo"
opt.timeoutlen = 300             -- ms to wait for a mapped key sequence
opt.updatetime = 200             -- ms before CursorHold triggers (faster for LSP/gitsigns)
opt.completeopt = { "menu", "menuone", "noselect" }
opt.shortmess:append("c")        -- hide completion messages
opt.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize"

-- Ensure undo directory exists
vim.fn.mkdir(opt.undodir:get(), "p")
