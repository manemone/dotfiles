-- mini.lua — mini.nvim family (replaces vim-surround, lexima.vim, etc.)

return {
  "echasnovski/mini.nvim",
  version = false, -- use stable branch for updates
  event = "VeryLazy",
  config = function()
    -- ── mini.surround (replaces tpope/vim-surround) ────────────────────
    -- sa, sd, sr operators: saiw" → surround word with "
    require("mini.surround").setup({
      mappings = {
        add = "sa",
        delete = "sd",
        find = "sf",
        find_left = "sF",
        highlight = "sh",
        replace = "sr",
        update_n_lines = "sn",
      },
    })

    -- ── mini.pairs (replaces lexima.vim auto-pairs) ────────────────────
    -- Auto-close brackets, quotes, etc.
    require("mini.pairs").setup()

    -- ── mini.ai (better text objects — used by mini.surround) ──────────
    require("mini.ai").setup()

    -- ── mini.icons (for lualine, telescope, etc.) ──────────────────────
    require("mini.icons").setup()

    -- ── mini.statusline — disabled (we use lualine) ────────────────────
    -- require("mini.statusline").setup() -- skip; lualine is used instead
  end,
}
