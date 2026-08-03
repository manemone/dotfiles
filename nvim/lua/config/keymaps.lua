-- keymaps.lua — all key mappings (translated from init.vim)
-- Leader: <Space>

local map = vim.keymap.set

-- ── Leader-key shortcuts ──────────────────────────────────────────────

-- File operations
map("n", "<Leader>w", "<Cmd>write<CR>", { desc = "Save buffer" })

-- Whether `a` and `b` resolve to the same file on disk (case-only rename on
-- a case-insensitive filesystem, "./foo" vs "foo", ...).
local function same_file(a, b)
  local a_st = vim.uv.fs_stat(vim.fn.fnamemodify(a, ":p"))
  local b_st = vim.uv.fs_stat(vim.fn.fnamemodify(b, ":p"))
  return a_st ~= nil and b_st ~= nil and a_st.ino == b_st.ino and a_st.dev == b_st.dev
end

-- Rename the current file in place. Ported from the pre-lazy.nvim init.vim's
-- RenameCurrentFile(), but using a filesystem rename instead of :saveas +
-- delete() — the latter deletes the file it just wrote if the new name
-- resolves to the same file (e.g. a case-only change on a case-insensitive
-- filesystem, or "./foo" while editing "foo").
-- <Leader>n, not to be confused with <Leader>rn (LSP rename) in lsp.lua.
local function rename_current_file()
  local old_name = vim.fn.expand("%")
  local new_name = vim.fn.input("New filename: ", old_name, "file")
  if new_name == "" or new_name == old_name then
    return
  end

  if old_name == "" or vim.fn.filereadable(old_name) == 0 then
    -- Unnamed or not-yet-written buffer: nothing on disk to rename away
    -- from, just give the buffer a name and save it. magic disabled so a
    -- literal "%" or "#" in new_name isn't expanded into the current or
    -- alternate filename.
    local ok, err = pcall(function()
      vim.cmd({ cmd = "saveas", args = { new_name }, magic = { file = false, bar = false } })
    end)
    if not ok then
      if old_name ~= "" then
        vim.api.nvim_buf_set_name(0, old_name)
      end
      vim.notify("Rename failed: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    vim.cmd.redraw()
    return
  end

  -- Refuse to silently clobber a different existing file — vim.fn.rename()
  -- below is a plain rename(2) wrapper and overwrites without asking. A
  -- same-file "rename" (case-only, "./foo" vs "foo", ...) is still allowed.
  -- fs_lstat (not filereadable/isdirectory, and not fs_stat) so this also
  -- catches directory entries we can't read the contents of — an unreadable
  -- file, a broken symlink — since rename(2) only cares about the parent
  -- directory's permissions, not the target's.
  if
    vim.uv.fs_lstat(vim.fn.fnamemodify(new_name, ":p")) ~= nil
    and not same_file(old_name, new_name)
  then
    vim.notify("Rename aborted: " .. new_name .. " already exists", vim.log.levels.ERROR)
    return
  end

  -- A buffer with the target name may already be open (even if nothing on
  -- disk has that name yet, e.g. an unsaved `:e draft.md`). Renaming onto it
  -- anyway would leave nvim_buf_set_name() below to fail with E95 *after*
  -- the file has already been moved on disk.
  if vim.fn.bufexists(new_name) == 1 and vim.fn.bufnr(new_name) ~= vim.api.nvim_get_current_buf() then
    vim.notify("Rename aborted: a buffer named " .. new_name .. " is already open", vim.log.levels.ERROR)
    return
  end

  -- Flush pending edits before moving the file, so the rename carries the
  -- latest content.
  if vim.bo.modified then
    local ok, err = pcall(vim.cmd.write)
    if not ok then
      vim.notify("Rename aborted: could not save " .. old_name .. ": " .. tostring(err), vim.log.levels.ERROR)
      return
    end
  end

  if vim.fn.rename(old_name, new_name) ~= 0 then
    vim.notify("Rename failed: could not rename " .. old_name .. " to " .. new_name, vim.log.levels.ERROR)
    return
  end

  -- nvim_buf_set_name() alone leaves the buffer "not edited", which makes a
  -- subsequent :write fail with E13. :edit! re-reads the (just-renamed)
  -- file under its new name and clears that state. Both are pcall'd because
  -- the file has already been moved on disk at this point — if updating the
  -- buffer fails (e.g. E95, a same-named buffer slipped past the bufexists
  -- check above via a race), the editor's state would otherwise silently
  -- fall out of sync with what's on disk.
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_name(0, new_name)
    vim.cmd.edit({ bang = true })
  end)
  if not ok then
    vim.notify(
      "Renamed " .. old_name .. " to " .. new_name .. " on disk, but could not update the buffer: " .. tostring(err),
      vim.log.levels.ERROR
    )
    return
  end
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
