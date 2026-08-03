-- lsp.lua — Built-in LSP configuration (replaces coc.nvim)
-- Uses mason.nvim for server installs, nvim-lspconfig for wiring.

return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },
  config = function()
    -- ── LSP keymaps (on_attach) ──────────────────────────────────────────

    local on_attach = function(client, bufnr)
      local buf = bufnr
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
      end

      -- Navigation
      map("n", "gd", vim.lsp.buf.definition, "Go to definition")
      map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
      map("n", "gr", vim.lsp.buf.references, "Go to references")
      map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
      map("n", "<Leader>D", vim.lsp.buf.type_definition, "Type definition")

      -- Hover / signature
      map("n", "K", vim.lsp.buf.hover, "Hover")
      map("i", "<Leader>k", vim.lsp.buf.signature_help, "Signature help")

      -- Actions
      map("n", "<Leader>rn", vim.lsp.buf.rename, "Rename")
      map("n", "<Leader>ca", vim.lsp.buf.code_action, "Code action")
      map("v", "<Leader>ca", vim.lsp.buf.code_action, "Code action")

      -- Diagnostics
      map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
      map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
      map("n", "<Leader>e", vim.diagnostic.open_float, "Show diagnostic float")

      -- Workspace
      map("n", "<Leader>wa", vim.lsp.buf.add_workspace_folder, "Add workspace folder")
      map("n", "<Leader>wr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
      map("n", "<Leader>wl", function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
      end, "List workspace folders")

      -- Format
      map("n", "<Leader>f", function()
        vim.lsp.buf.format({ async = true })
      end, "Format buffer")

      -- Highlight references under cursor
      if client.server_capabilities.documentHighlightProvider then
        local hl_augroup = vim.api.nvim_create_augroup("LspHighlight", { clear = false })
        vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
          group = hl_augroup,
          buffer = buf,
          callback = vim.lsp.buf.document_highlight,
        })
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
          group = hl_augroup,
          buffer = buf,
          callback = vim.lsp.buf.clear_references,
        })
      end
    end

    -- ── Diagnostic UI ─────────────────────────────────────────────────────

    vim.diagnostic.config({
      virtual_text = true,
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = {
        border = "rounded",
        source = true,
      },
    })

    -- Diagnostic signs
    local signs = {
      { name = "DiagnosticSignError", text = " " },
      { name = "DiagnosticSignWarn",  text = " " },
      { name = "DiagnosticSignInfo",  text = " " },
      { name = "DiagnosticSignHint",  text = " " },
    }
    for _, sign in ipairs(signs) do
      vim.fn.sign_define(sign.name, { texthl = sign.name, text = sign.text, numhl = sign.name })
    end

    -- ── LSP capabilities (advertise blink.cmp's completion support) ───────
    -- require("blink.cmp") triggers lazy.nvim to load the plugin here if it
    -- hasn't been loaded yet (lazy.nvim indexes every plugin's module path
    -- regardless of its own lazy-load event). blink.cmp's (and, via its
    -- dependency, LuaSnip's) `event` in their own plugin files is set to
    -- match this file's BufReadPre/BufNewFile rather than InsertEnter,
    -- since this require forces that load anyway.
    local capabilities = require("blink.cmp").get_lsp_capabilities()

    -- ── mason.nvim ────────────────────────────────────────────────────────

    require("mason").setup({
      ui = {
        border = "rounded",
        icons = {
          package_installed = " ",
          package_pending = " ",
          package_uninstalled = " ",
        },
      },
    })

    -- ── mason-lspconfig (bridge) ──────────────────────────────────────────

    require("mason-lspconfig").setup({
      ensure_installed = {
        "lua_ls",
        "rust_analyzer",
        "ts_ls",
        "volar",
        "pyright",
        "gopls",
        "ruby_lsp",
        "jsonls",
        "yamlls",
        "taplo",
        "bashls",
        "zls",
        "marksman",
      },
      -- mason-lspconfig v2 enables every installed server automatically
      -- via vim.lsp.enable(); per-server settings come from vim.lsp.config
      -- below.
      automatic_enable = true,
    })

    -- ── mason-tool-installer (auto-install formatters/linters) ────────────

    require("mason-tool-installer").setup({
      ensure_installed = {
        "stylua",
        "shfmt",
        -- "prettierd",
        -- "eslint_d",
      },
      auto_update = false,
      run_on_start = true,
    })

    -- ── Server configs ────────────────────────────────────────────────────

    -- Defaults applied to every server. mason-lspconfig v2 replaced
    -- setup_handlers() with vim.lsp.config()/vim.lsp.enable(), so shared
    -- settings go into the "*" pseudo-server.
    vim.lsp.config("*", {
      on_attach = on_attach,
      capabilities = capabilities,
    })

    -- Per-server overrides (merged on top of "*")
    vim.lsp.config("lua_ls", {
      settings = {
        Lua = {
          runtime = { version = "LuaJIT" },
          diagnostics = { globals = { "vim" } },
          workspace = {
            library = vim.api.nvim_get_runtime_file("", true),
            checkThirdParty = false,
          },
          telemetry = { enable = false },
          completion = { callSnippet = "Replace" },
        },
      },
    })
  end,
}
