return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons", "folke/noice.nvim" },
	opts = function()
		local noice = require("noice")

		return {
			options = {
				theme = "auto",
			},
			sections = {
				lualine_x = {
					{
						noice.api.status.message.get_hl,
						cond = noice.api.status.message.has,
					},
					{
						noice.api.status.command.get,
						cond = noice.api.status.command.has,
						color = { fg = "#ff9e64" },
					},
					{
						noice.api.status.mode.get,
						cond = noice.api.status.mode.has,
						color = { fg = "#ff9e64" },
					},
					{
						noice.api.status.search.get,
						cond = noice.api.status.search.has,
						color = { fg = "#ff9e64" },
					},
				},
			},
		}
	end,
}
