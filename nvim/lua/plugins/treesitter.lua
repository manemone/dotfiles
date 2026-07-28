-- treesitter.lua — Syntax highlighting (replaces filetype-specific syntax plugins)

return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter-textobjects",
  },
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "vimdoc",
      "query",
      "bash",
      "c",
      "cpp",
      "css",
      "diff",
      "go",
      "html",
      "javascript",
      "jsdoc",
      "json",
      "jsonc",
      "make",
      "markdown",
      "markdown_inline",
      "python",
      "regex",
      "ruby",
      "rust",
      "scss",
      "sql",
      "toml",
      "tsx",
      "typescript",
      "vue",
      "yaml",
      "zig",
    },
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = false,
    },
    indent = {
      enable = true,
    },
    textobjects = {
      select = {
        enable = true,
        lookahead = true,
        keymaps = {
          ["af"] = "@function.outer",
          ["if"] = "@function.inner",
          ["ac"] = "@class.outer",
          ["ic"] = "@class.inner",
        },
      },
      swap = {
        enable = true,
        swap_next = { ["<Leader>sn"] = "@parameter.inner" },
        swap_previous = { ["<Leader>sp"] = "@parameter.inner" },
      },
      move = {
        enable = true,
        set_jumps = true,
        goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer" },
        goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer" },
      },
    },
  },
  config = function(_, opts)
    require("nvim-treesitter.configs").setup(opts)
  end,
}
