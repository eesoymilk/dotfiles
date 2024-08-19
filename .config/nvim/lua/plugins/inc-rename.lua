return {
	"smjonas/inc-rename.nvim",
	keys = {
		{
			"<leader>rn",
			function()
				return ":IncRename " .. vim.fn.expand("<cword>")
			end,
			expr = true,
		},
	},
	config = true,
}
