return {
  {
    "mason-org/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()
      -- Formatters conform.nvim calls; mason-lspconfig only installs servers.
      local registry = require("mason-registry")
      registry.refresh(function()
        for _, name in ipairs({ "stylua" }) do
          local pkg = registry.get_package(name)
          if not pkg:is_installed() then
            pkg:install()
          end
        end
      end)
    end,
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = { "onsails/lspkind-nvim" },
    config = function()
      local cmp = require("cmp")
      local lspkind = require("lspkind")

      local has_words_before = function()
        if vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt" then
          return false
        end
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0
          and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
      end

      cmp.setup({
        sources = {
          { name = "nvim_lsp" },
        },
        formatting = {
          format = lspkind.cmp_format({
            mode = "symbol",
            max_width = 50,
          }),
        },
        mapping = cmp.mapping.preset.insert({
          ["<CR>"] = cmp.mapping.confirm({
            -- documentation says this is important.
            -- I don't know why.
            behavior = cmp.ConfirmBehavior.Replace,
            select = false,
          }),
          ["<C-u>"] = cmp.mapping.scroll_docs(-4),
          ["<C-d>"] = cmp.mapping.scroll_docs(4),
          ["<C-f>"] = cmp.mapping(function(fallback)
            if vim.snippet.active({ direction = 1 }) then
              vim.snippet.jump(1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<C-b>"] = cmp.mapping(function(fallback)
            if vim.snippet.active({ direction = -1 }) then
              vim.snippet.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<C-l>"] = cmp.mapping.complete(),
          ["<C-j>"] = function(fallback)
            if cmp.visible() then
              cmp.select_next_item({
                behavior = cmp.SelectBehavior.Select,
              })
            else
              fallback()
            end
          end,
          ["<C-k>"] = function(fallback)
            if cmp.visible() then
              cmp.select_prev_item({
                behavior = cmp.SelectBehavior.Select,
              })
            else
              fallback()
            end
          end,
          ["<Tab>"] = vim.schedule_wrap(function(fallback)
            if cmp.visible() and has_words_before() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            else
              fallback()
            end
          end),
        }),
        snippet = {
          expand = function(args)
            vim.snippet.expand(args.body)
          end,
        },
      })
    end,
  },

  -- LSP
  {
    "neovim/nvim-lspconfig",
    cmd = { "LspInfo", "LspInstall", "LspStart" },
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "hrsh7th/cmp-nvim-lsp",
      "mason-org/mason-lspconfig.nvim",
    },
    config = function()
      vim.diagnostic.config({
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "✘",
            [vim.diagnostic.severity.WARN] = "▲",
            [vim.diagnostic.severity.HINT] = "⚑",
            [vim.diagnostic.severity.INFO] = "»",
          },
        },
      })

      local capabilities = vim.tbl_deep_extend("force", require("cmp_nvim_lsp").default_capabilities(), {
        textDocument = {
          foldingRange = {
            dynamicRegistration = false,
            lineFoldingOnly = true,
          },
        },
      })

      vim.lsp.config("*", { capabilities = capabilities })
      vim.lsp.config("tailwindcss", {
        root_markers = { ".git" },
      })
      vim.lsp.config("ts_ls", {
        root_markers = { ".git" },
        workspace_required = true,
      })
      -- Each Python project carries its own uv-managed .venv; point Pyright at
      -- it so imports resolve per project instead of against the system python.
      vim.lsp.config("pyright", {
        before_init = function(_, config)
          local python = config.root_dir and config.root_dir .. "/.venv/bin/python"
          if not python or not vim.uv.fs_stat(python) then
            return
          end
          config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
            python = { pythonPath = python },
          })
        end,
      })
      vim.lsp.config("tinymist", {
        settings = {
          exportPdf = "onType",
          formatterMode = "typstyle",
        },
      })

      require("mason").setup({})
      -- mason-lspconfig v2 auto-enables installed servers via vim.lsp.enable()
      require("mason-lspconfig").setup({
        ensure_installed = { "tinymist", "pyright", "ruff", "ts_ls", "lua_ls" },
      })
    end,
  },
}
