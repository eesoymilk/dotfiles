return {
	"rcarriga/nvim-notify",
	config = function()
		require("notify").setup({
			timeout = 5000,
			background_colour = "#000000",
			render = "wrapped-compact",
		})
		vim.notify = require("notify")
	end,
}
