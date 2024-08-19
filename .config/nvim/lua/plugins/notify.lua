return {
	"rcarriga/nvim-notify",
	opts = {
		timeout = 5000,
		background_colour = "#000000",
		render = "wrapped-compact",
	},
	config = function(opts)
		require("notify").setup(opts)
		vim.notify = require("notify")
	end,
}
