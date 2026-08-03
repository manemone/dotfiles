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

    -- <Tab> / <S-Tab> placeholder navigation is bound by blink.cmp's
    -- "default" keymap preset (snippet_forward/snippet_backward, falling
    -- back to a literal Tab outside a snippet) — see lua/plugins/blink.lua.
    -- No manual mapping here to avoid two plugins fighting over <Tab>.

    -- <C-k> expand (keeps compatibility with old neosnippet mapping)
    vim.keymap.set({ "i", "s" }, "<C-k>", function()
      if luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      end
    end, { silent = true, desc = "LuaSnip: expand or jump" })
  end,
}
