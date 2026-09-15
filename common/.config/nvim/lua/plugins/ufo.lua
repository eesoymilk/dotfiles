return {
	"kevinhwang91/nvim-ufo",
	dependencies = { "kevinhwang91/promise-async" },
	-- Must be loaded before the first file is read: attaching to a buffer that
	-- is still empty (e.g. from a BufReadPre-triggered load) leaves ufo with a
	-- stale line cache and no folds for that buffer.
	lazy = false,
	keys = {
		{ "zR", function() require("ufo").openAllFolds() end, desc = "Open all folds." },
		{ "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds." },
		{ "zr", function() require("ufo").openFoldsExceptKinds() end, desc = "Open fold." },
		{ "zm", function() require("ufo").closeFoldsWith() end, desc = "Close fold." },
	},
	config = function()
		vim.o.foldcolumn = "1" -- '0' is not bad
		vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
		vim.o.foldlevelstart = 99
		vim.o.foldenable = true
		require("ufo").setup()
	end,
}
