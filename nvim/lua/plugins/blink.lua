-- blink.lua — Completion popup + fuzzy matching (restores auto-popup lost
-- when coc.nvim was replaced with built-in LSP; <C-x><C-o> was the only
-- fallback until now).
--
-- Chosen over nvim-cmp: blink.cmp bundles lsp/path/snippets/buffer sources
-- in one plugin (no separate cmp-nvim-lsp/cmp-buffer/cmp-path/cmp_luasnip
-- to track), matches this repo's "built-in first, few dependencies"
-- philosophy (see nvim/README.md), and its fuzzy matcher is Rust-backed.

return {
  "saghen/blink.cmp",
  event = "InsertEnter",
  version = "1.*",
  dependencies = { "L3MON4D3/LuaSnip" },
  opts = {
    -- "default" preset binds <Tab>/<S-Tab> to snippet_forward/snippet_backward
    -- (falling back to a literal Tab when not inside a snippet). This is why
    -- the manual <Tab>/<S-Tab> mappings were removed from luasnip.lua — blink
    -- now owns those keys.
    keymap = { preset = "default" },
    completion = {
      documentation = { auto_show = true },
    },
    -- Expand/jump through LuaSnip (already installed) instead of blink's
    -- own snippet engine.
    snippets = { preset = "luasnip" },
  },
}
