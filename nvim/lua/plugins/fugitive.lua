-- fugitive.lua — Git integration (vim-fugitive + vim-rhubarb)

return {
  "tpope/vim-fugitive",
  cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gclog", "Gblame" },
  keys = {
    { "<Leader>gs", "<Cmd>Git<CR>",   desc = "Git status" },
    { "<Leader>gb", "<Cmd>Git blame<CR>", desc = "Git blame" },
    { "<Leader>gc", "<Cmd>Git commit<CR>", desc = "Git commit" },
    { "<Leader>gp", "<Cmd>Git push<CR>",  desc = "Git push" },
  },
  dependencies = {
    "tpope/vim-rhubarb", -- GitHub :Gbrowse support
  },
}
