return {
	{
		"VonHeikemen/lsp-zero.nvim",
		branch = "v4.x",
		lazy = true,
		config = false,
	},
	{
		"williamboman/mason.nvim",
		lazy = false,
		config = true,
		-- opts = {
		--     ensure_installed = {
		--         "clang-format",
		--         "stylua",
		--         "prettierd",
		--         "rustywind",
		--     },
		-- },
		-- config = function(_, opts)
		--     require("mason").setup(opts)
		--     local mr = require("mason-registry")
		--     mr:on("package:install:success", function()
		--         vim.defer_fn(function()
		--             -- trigger FileType event to possibly load this
		--             -- newly installed LSP server
		--             require("lazy.core.handler.event").trigger({
		--                 event = "FileType",
		--                 buf = vim.api.nvim_get_current_buf(),
		--             })
		--         end, 100)
		--     end)
		--     local function ensure_installed()
		--         for _, tool in ipairs(opts.ensure_installed) do
		--             local p = mr.get_package(tool)
		--             if not p:is_installed() then
		--                 p:install()
		--             end
		--         end
		--     end
		--     if mr.refresh then
		--         mr.refresh(ensure_installed)
		--     else
		--         ensure_installed()
		--     end
		-- end,
	},

	-- Autocompletion
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = { "L3MON4D3/LuaSnip", "onsails/lspkind-nvim" },
		config = function()
			local cmp = require("cmp")
			local lspkind = require("lspkind")
			local cmp_action = require("lsp-zero").cmp_action()

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
					{ name = "luasnip" },
					{ name = "copilot" },
				},
				formatting = {
					format = lspkind.cmp_format({
						mode = "symbol",
						max_width = 50,
						symbol_map = { Copilot = "" },
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
					["<C-f>"] = cmp_action.luasnip_jump_forward(),
					["<C-b>"] = cmp_action.luasnip_jump_backward(),
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
			"williamboman/mason.nvim",
			"hrsh7th/cmp-nvim-lsp",
			"williamboman/mason-lspconfig.nvim",
			"kevinhwang91/nvim-ufo",
		},
		config = function()
			-- This is where all the LSP shenanigans will live
			local lsp_zero = require("lsp-zero")

			local lsp_attach = function(client, bufnr)
				lsp_zero.default_keymaps({ buffer = bufnr })
			end

			local lsp_capabilities = vim.tbl_deep_extend("force", require("cmp_nvim_lsp").default_capabilities(), {
				textDocument = {
					foldingRange = {
						dynamicRegistration = false,
						lineFoldingOnly = true,
					},
				},
			})

			lsp_zero.extend_lspconfig({
				sign_text = {
					error = "✘",
					warn = "▲",
					hint = "⚑",
					info = "»",
				},
				lsp_attach = lsp_attach,
				capabilities = lsp_capabilities,
			})

			require("mason").setup({})
			require("mason-lspconfig").setup({
				ensure_installed = {
					"tsserver",
					"clangd",
					"rust_analyzer",
					"eslint",
					"lua_ls",
					"svelte",
					"tailwindcss",
				},
				handlers = {
					function(server_name)
						require("lspconfig")[server_name].setup({})
					end,
				},
			})
		end,
	},
}
