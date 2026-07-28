-- treesitter.lua — Syntax highlighting (replaces filetype-specific syntax plugins)

return {
  "nvim-treesitter/nvim-treesitter",
  -- Pin to the module-based branch. The `main` branch is a rewrite that
  -- dropped `nvim-treesitter.configs` and every module configured below.
  branch = "master",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = {
    { "nvim-treesitter/nvim-treesitter-textobjects", branch = "master" },
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
    -- Incremental selection (replaces terryma/vim-expand-region).
    -- Keys match the old dein.toml mappings: v expands, <C-v> shrinks.
    -- Expansion follows the syntax tree, so it grows word → expression →
    -- argument → call → function rather than by regex heuristics.
    incremental_selection = {
      enable = true,
      keymaps = {
        init_selection = "v",
        node_incremental = "v",
        node_decremental = "<C-v>",
        scope_incremental = false,
      },
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
