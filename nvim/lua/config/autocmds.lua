-- autocmds.lua — automatic commands
-- Kept minimal: NeoVim defaults are good enough for most things.

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local general = augroup("General", { clear = true })

-- ── Restore cursor position on file re-open ────────────────────────────

autocmd("BufReadPost", {
  group = general,
  desc = "Restore cursor position",
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 1 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- ── Highlight on yank ─────────────────────────────────────────────────

autocmd("TextYankPost", {
  group = general,
  desc = "Briefly highlight yanked region",
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

-- ── Trim trailing whitespace on save ────────────────────────────────────

autocmd("BufWritePre", {
  group = general,
  desc = "Trim trailing whitespace on save",
  pattern = { "*.lua", "*.vim", "*.py", "*.rb", "*.rs", "*.js", "*.ts", "*.jsx", "*.tsx", "*.go", "*.sh", "*.zsh", "*.toml", "*.yaml", "*.yml", "*.json", "*.md" },
  command = [[%s/\s\+$//e]],
})

-- ── Return to last edit position on commit message ─────────────────────

autocmd("FileType", {
  group = general,
  pattern = "gitcommit",
  desc = "Start gitcommit at top of file",
  callback = function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end,
})

-- ── Resize splits on VimResized ─────────────────────────────────────────

autocmd("VimResized", {
  group = general,
  desc = "Equalize window sizes on terminal resize",
  command = "wincmd =",
})

-- ── Close some filetypes with q ─────────────────────────────────────────

autocmd("FileType", {
  group = general,
  pattern = { "help", "lspinfo", "man", "qf", "checkhealth", "fugitive", "git" },
  desc = "Close window with q",
  callback = function()
    vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = true, silent = true, desc = "Close window" })
  end,
})
