-- init.lua — NeoVim configuration entry point
-- Powered by lazy.nvim (lightweight glue), mini.nvim (small features),
-- and NeoVim built-in capabilities wherever possible.

-- ── Early setup (before lazy.nvim) ─────────────────────────────────────

-- Leader key (must be set before lazy.nvim loads plugin keymaps)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Python 3 provider: auto-detect via mise or system python3
local function find_python3()
  -- Try mise-managed python first
  local handle = io.popen("mise where python 2>/dev/null")
  if handle then
    local mise_dir = handle:read("*a"):gsub("%s+$", "")
    handle:close()
    if mise_dir ~= "" then
      -- mise where returns the version dir; python3 binary is inside bin/
      local bin = mise_dir .. "/bin/python3"
      if vim.fn.filereadable(bin) == 1 then
        return bin
      end
      local py = mise_dir .. "/bin/python"
      if vim.fn.filereadable(py) == 1 then
        return py
      end
    end
  end
  -- Fall back to system python3
  local handle2 = io.popen("which python3 2>/dev/null || which python 2>/dev/null")
  if handle2 then
    local result = handle2:read("*a"):gsub("%s+$", "")
    handle2:close()
    if result ~= "" then
      return result
    end
  end
  return nil
end

local python3 = find_python3()
if python3 then
  vim.g.python3_host_prog = python3
end

-- ── Load configuration modules ─────────────────────────────────────────

require("config.options")
require("config.keymaps")
require("config.autocmds")

-- ── lazy.nvim bootstrap ────────────────────────────────────────────────

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim (shell_error=" .. vim.v.shell_error .. ")\n", "ErrorMsg" },
      { "Check your network connection or install lazy.nvim manually:\n", "WarningMsg" },
      { "  git clone --filter=blob:none https://github.com/folke/lazy.nvim.git --branch=stable " .. lazypath, "MoreMsg" },
    }, true, {})
  end
end
vim.opt.rtp:prepend(lazypath)

-- ── Plugin specs ───────────────────────────────────────────────────────
-- Each plugin gets its own file under lua/plugins/.
-- lazy.nvim is used ONLY as glue: lazy-loading + lockfile.
-- Small features → mini.nvim.  Everything else → NeoVim built-in.

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  defaults = {
    lazy = true, -- everything lazy by default
  },
  install = {
    colorscheme = { "dracula" },
  },
  checker = {
    enabled = true,
    notify = false,
  },
  change_detection = {
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
