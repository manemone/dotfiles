-- luasnip.lua — Snippet engine (replaces neosnippet)

return {
  "L3MON4D3/LuaSnip",
  version = "v2.*",
  event = "InsertEnter",
  dependencies = {
    "rafamadriz/friendly-snippets",
  },
  opts = {
    history = true,
    delete_check_events = "TextChanged",
  },
  config = function(_, opts)
    local luasnip = require("luasnip")
    luasnip.setup(opts)

    -- Load friendly-snippets (VS Code-compatible snippet collection)
    require("luasnip.loaders.from_vscode").lazy_load()

    -- ── Key mappings ────────────────────────────────────────────────────

    -- <Tab> / <S-Tab> to navigate snippet placeholders
    vim.keymap.set({ "i", "s" }, "<Tab>", function()
      if luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      else
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<Tab>", true, false, true),
          "n",
          false
        )
      end
    end, { silent = true, desc = "LuaSnip: expand or jump forward" })

    vim.keymap.set({ "i", "s" }, "<S-Tab>", function()
      if luasnip.jumpable(-1) then
        luasnip.jump(-1)
      else
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true),
          "n",
          false
        )
      end
    end, { silent = true, desc = "LuaSnip: jump backward" })

    -- <C-k> expand (keeps compatibility with old neosnippet mapping)
    vim.keymap.set({ "i", "s" }, "<C-k>", function()
      if luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      end
    end, { silent = true, desc = "LuaSnip: expand or jump" })
  end,
}
