return {
	"lervag/vimtex",
	lazy = false, -- we don't want to lazy load VimTeX
	-- tag = "v2.15", -- uncomment to pin to a specific release
	init = function()
		-- PDF viewer differs per OS: Skim on macOS, Okular elsewhere.
		if vim.fn.has("mac") == 1 then
			vim.g.vimtex_view_method = "skim"
		else
			vim.g.vimtex_view_general_viewer = "okular"
			vim.g.vimtex_view_general_options = "--unique file:@pdf#src:@line@tex"
		end
	end,
}
