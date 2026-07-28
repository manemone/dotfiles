-- dracula.lua — Dracula colorscheme (replaces molokai)

return {
  "Mofiqul/dracula.nvim",
  lazy = false, -- colorscheme must load immediately
  priority = 1000,
  opts = {
    colors = {
      bg = "#282a36", -- use the classic dracula bg
    },
    transparent_bg = false,
    show_end_of_buffer = true,
  },
  config = function(_, opts)
    require("dracula").setup(opts)
    vim.cmd.colorscheme("dracula")
  end,
}
