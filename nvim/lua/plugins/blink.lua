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
  -- lsp.lua requires("blink.cmp") to build LSP capabilities, which lazy.nvim
  -- resolves by loading this plugin immediately on BufReadPre/BufNewFile —
  -- before the InsertEnter event below would otherwise fire. Declaring the
  -- event lsp.lua actually forces keeps this honest instead of claiming a
  -- lazy-load that doesn't happen.
  event = { "BufReadPre", "BufNewFile" },
  version = "1.*",
  dependencies = { "L3MON4D3/LuaSnip" },
  opts = {
    keymap = {
      -- "default" preset binds <Tab>/<S-Tab> to snippet_forward/snippet_backward
      -- (movement through an already-expanded snippet's placeholders only —
      -- falling back to a literal Tab otherwise). This is why the manual
      -- <Tab>/<S-Tab> mappings were removed from luasnip.lua — blink now owns
      -- those keys. Snippet *expansion* is not on <Tab>; it's <C-k> below.
      preset = "default",
      -- "default" also binds <C-k> to show/hide signature help with a
      -- fallback, which would otherwise shadow luasnip.lua's global <C-k>
      -- snippet-expand mapping (currently invisible only because
      -- signature.enabled defaults to false). Release it back to LuaSnip.
      ["<C-k>"] = false,
    },
    completion = {
      documentation = { auto_show = true },
    },
    -- Expand/jump through LuaSnip (already installed) instead of blink's
    -- own snippet engine.
    snippets = { preset = "luasnip" },
  },
}
