-- telescope.lua — Fuzzy finder (replaces Denite / CtrlP)

return {
  "nvim-telescope/telescope.nvim",
  branch = "0.1.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      cond = function()
        return vim.fn.executable("make") == 1
      end,
    },
  },
  cmd = "Telescope",
  keys = {
    { "<Leader>o",  "<Cmd>Telescope find_files<CR>",        desc = "Find files" },
    { "<Leader>ff", "<Cmd>Telescope find_files<CR>",        desc = "Find files" },
    { "<Leader>fg", "<Cmd>Telescope live_grep<CR>",         desc = "Live grep" },
    { "<Leader>fb", "<Cmd>Telescope buffers<CR>",           desc = "Buffers" },
    { "<Leader>fh", "<Cmd>Telescope help_tags<CR>",         desc = "Help tags" },
    { "<Leader>fd", "<Cmd>Telescope diagnostics<CR>",       desc = "Diagnostics" },
    { "<Leader>fs", "<Cmd>Telescope lsp_document_symbols<CR>", desc = "Symbols" },
    { "<Leader>d",  "<Cmd>Telescope buffers<CR>",           desc = "Buffers (Denite compat)" },
    { "<Leader>g",  "<Cmd>Telescope live_grep<CR>",         desc = "Live grep (Denite compat)" },
  },
  opts = {
    defaults = {
      mappings = {
        i = {
          ["<C-j>"] = "move_selection_next",
          ["<C-k>"] = "move_selection_previous",
          ["<C-n>"] = "move_selection_next",
          ["<C-p>"] = "move_selection_previous",
        },
      },
      layout_strategy = "horizontal",
      layout_config = {
        horizontal = { prompt_position = "top", preview_width = 0.55 },
      },
      sorting_strategy = "ascending",
      file_ignore_patterns = {
        "node_modules/",
        ".git/",
        "%.o",
        "%.class",
      },
    },
    pickers = {
      buffers = {
        sort_lastused = true,
        mappings = {
          i = {
            ["<C-d>"] = "delete_buffer",
          },
        },
      },
    },
    extensions = {
      fzf = {
        fuzzy = true,
        override_generic_sorter = true,
        override_file_sorter = true,
        case_mode = "smart_case",
      },
    },
  },
  config = function(_, opts)
    local telescope = require("telescope")
    telescope.setup(opts)
    pcall(telescope.load_extension, "fzf")
  end,
}
