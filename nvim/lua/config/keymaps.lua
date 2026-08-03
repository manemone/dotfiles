-- keymaps.lua — all key mappings (translated from init.vim)
-- Leader: <Space>

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- ── Leader-key shortcuts ──────────────────────────────────────────────

-- File operations
map("n", "<Leader>w", "<Cmd>write<CR>", { desc = "Save buffer" })

-- Rename the current file in place (:saveas to the new name, delete the old
-- one). Ported from the pre-lazy.nvim init.vim's RenameCurrentFile().
-- <Leader>n, not to be confused with <Leader>rn (LSP rename) in lsp.lua.
local function rename_current_file()
  local old_name = vim.fn.expand("%")
  local new_name = vim.fn.input("New filename: ", old_name, "file")
  if new_name == "" or new_name == old_name then
    return
  end
  vim.cmd.saveas(new_name)
  vim.fn.delete(old_name)
  vim.cmd.redraw()
end
map("n", "<Leader>n", rename_current_file, { desc = "Rename current file" })

-- NOTE: Telescope keymaps are defined in lua/plugins/telescope.lua (lazy.nvim `keys`).
-- They are NOT duplicated here to avoid dead code from lazy-loading key override.

-- Clipboard: system clipboard operations
map("v", "<Leader>y", '"+y', { desc = "Yank to system clipboard" })
map("v", "<Leader>d", '"+d', { desc = "Cut to system clipboard" })
map("n", "<Leader>p", '"+p', { desc = "Paste from system clipboard" })
map("n", "<Leader>P", '"+P', { desc = "Paste before from system clipboard" })
map("v", "<Leader>p", '"+p', { desc = "Paste from system clipboard" })
map("v", "<Leader>P", '"+P', { desc = "Paste before from system clipboard" })

-- Visual line mode
map("n", "<Leader><Leader>", "V", { desc = "Visual line mode" })

-- Yank/paste: auto-goto end of changed text
map("v", "y", "y`]", { desc = "Yank → end" })
-- NOTE: Normal-mode "p" goes to end of pasted text.
-- Visual-mode "p" is overridden below by the paste-without-overwriting-register mapping.
map("n", "p", "p`]", { desc = "Paste → end" })

-- Select pasted text
map({ "n", "v" }, "gV", "`[v`]", { desc = "Select last pasted/yanked" })

-- ── Window navigation ─────────────────────────────────────────────────

-- Ctrl + hjkl
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })

-- Leader + hjkl
map("n", "<Leader>h", "<C-w>h", { desc = "Window left" })
map("n", "<Leader>j", "<C-w>j", { desc = "Window down" })
map("n", "<Leader>k", "<C-w>k", { desc = "Window up" })
map("n", "<Leader>l", "<C-w>l", { desc = "Window right" })

-- ── Window resize / move ──────────────────────────────────────────────

map("n", "<Leader>+", "<C-w>+", { desc = "Increase height" })
map("n", "<Leader>-", "<C-w>-", { desc = "Decrease height" })
map("n", "<Leader>vm", "<C-w>_", { desc = "Maximize vertical" })
map("n", "<Leader>hm", "<C-w>|", { desc = "Maximize horizontal" })
map("n", "<Leader>H", "<C-w>H", { desc = "Move window far-left" })
map("n", "<Leader>J", "<C-w>J", { desc = "Move window far-bottom" })
map("n", "<Leader>K", "<C-w>K", { desc = "Move window far-top" })
map("n", "<Leader>L", "<C-w>L", { desc = "Move window far-right" })

-- ── Terminal mode escape ──────────────────────────────────────────────

map("t", "<A-;>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
map("t", "<Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode (Esc)" })

-- ── Built-in commenting (NeoVim 0.10+) ────────────────────────────────

-- gc is the built-in comment operator (replaces nerdcommenter).
-- gcc  — toggle comment on current line
-- gcap — toggle comment on paragraph
-- gc   — toggle comment on visual selection
map("n", "<Leader>/", "gcc", { desc = "Toggle comment line" })
map("v", "<Leader>/", "gc", { desc = "Toggle comment selection" })

-- ── vp doesn't replace paste buffer ────────────────────────────────────

-- From original init.vim: preserve unnamed register when pasting over selection.
-- Normally in visual mode, pasting puts selected text into the unnamed register.
-- This mapping uses the black-hole register for the delete step so @" stays untouched.
map("v", "p", '"_dP', { desc = "Paste without overwriting register" })

-- ── LSP keymaps (set in lsp.lua plugin on_attach) ─────────────────────
-- See lua/plugins/lsp.lua for gd, gr, K, <Leader>rn, <Leader>ca, etc.
