return {
	"kevinhwang91/nvim-ufo",
	dependencies = { "kevinhwang91/promise-async" },
	keys = {
		{ "zR", require("ufo").openAllFolds, desc = "Open all folds." },
		{ "zM", require("ufo").closeAllFolds, desc = "Close all folds." },
		{ "zr", require("ufo").openFoldsExceptKinds, desc = "Open fold." },
		{ "zm", require("ufo").closeFoldsWith, desc = "Close fold." },
	},
	config = function()
		vim.o.foldcolumn = "1" -- '0' is not bad
		vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
		vim.o.foldlevelstart = 99
		vim.o.foldenable = true
		require("ufo").setup()
	end,
}
