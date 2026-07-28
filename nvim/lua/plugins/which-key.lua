-- which-key.lua — Keymap discovery popup

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "modern",
    delay = vim.o.timeoutlen,
    spec = {
      { "<Leader>c", group = "Code / Comment" },
      { "<Leader>f", group = "Find / Format" },
      { "<Leader>g", group = "Git" },
      { "<Leader>h", group = "Hunks (Git)" },
      { "<Leader>s", group = "Search / Surround" },
      { "<Leader>w", group = "Workspace / Write" },
    },
  },
}
