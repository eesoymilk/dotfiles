return {
	"numToStr/Comment.nvim",
	lazy = false,
	config = function(_, opts)
		require("Comment").setup(opts)
	end,
}
