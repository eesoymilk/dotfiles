return {
	"nvimtools/none-ls.nvim",
	event = "VeryLazy",
	keys = {
		{
			"<leader>fm",
			function()
				vim.lsp.buf.format({
					async = false,
					filter = function(client)
						return client.name == "null-ls"
					end,
				})
			end,
			desc = "Format",
		},
	},
	opts = function()
		local null_ls = require("null-ls")
		local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
		return {
			sources = {
				null_ls.builtins.formatting.stylua,
				null_ls.builtins.formatting.prettierd.with({
					extra_filetypes = { "astro", "svelte" },
				}),
				null_ls.builtins.formatting.rustywind.with({
					extra_filetypes = { "astro" },
				}),
			},
			on_attach = function(client, bufnr)
				if client.supports_method("textDocument/formatting") then
					vim.api.nvim_clear_autocmds({
						group = augroup,
						buffer = bufnr,
					})
					vim.api.nvim_create_autocmd("BufWritePre", {
						group = augroup,
						buffer = bufnr,
						callback = function()
							vim.lsp.buf.format({
								async = false,
								bufnr = bufnr,
							})
						end,
					})
				end
			end,
		}
	end,
	config = function(_, opts)
		require("null-ls").setup(opts)
	end,
}
