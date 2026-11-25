-- Search from the repo root rather than nvim's cwd, so opening nvim in a
-- subdirectory still covers the whole project. Falls back to cwd outside git.
local function project_root()
	return vim.fs.root(0, ".git") or vim.uv.cwd()
end

return {
	{
		"nvim-telescope/telescope.nvim",
		-- master, not the 0.1.x tags: 0.1.8 predates nvim-treesitter's `main`
		-- branch and calls the removed ft_to_lang API from its previewer.
		branch = "master",
		cond = not vim.g.vscode,
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-ui-select.nvim",
			{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
		},
		keys = {
			{
				"<leader>ff",
				function()
					require("telescope.builtin").find_files({ cwd = project_root() })
				end,
				desc = "Find project files",
			},
			{
				"<leader>gf",
				function()
					require("telescope.builtin").git_files({ cwd = project_root() })
				end,
				desc = "Find git files",
			},
			{
				"<leader>lg",
				function()
					require("telescope.builtin").live_grep({ cwd = project_root() })
				end,
				desc = "Live grep the project",
			},
			{
				"<leader>sd",
				function()
					require("telescope.builtin").diagnostics()
				end,
				desc = "Search diagnostics",
			},
			{
				"<leader>sk",
				function()
					require("telescope.builtin").keymaps()
				end,
				desc = "Search keymaps",
			},
			{
				"<leader>/",
				function()
					require("telescope.builtin").current_buffer_fuzzy_find()
				end,
				desc = "Fuzzy search buffer",
			},
			{
				"<leader>gs",
				function()
					require("telescope.builtin").git_status()
				end,
				desc = "Git status",
			},
			{
				"<leader>,",
				function()
					require("telescope.builtin").buffers()
				end,
				desc = "Find open buffers",
			},
			{
				"<leader>sw",
				function()
					require("telescope.builtin").grep_string()
				end,
				desc = "Search word under cursor",
			},
			{
				"<leader>sR",
				function()
					require("telescope.builtin").resume()
				end,
				desc = "Resume last picker",
			},
		},
		config = function()
			require("telescope").setup({
				defaults = {
					path_display = { "filename_first" },
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_dropdown({
							-- even more opts
						}),

						-- pseudo code / specification for writing custom displays, like the one
						-- for "codeactions"
						-- specific_opts = {
						--   [kind] = {
						--     make_indexed = function(items) -> indexed_items, width,
						--     make_displayer = function(widths) -> displayer
						--     make_display = function(displayer) -> function(e)
						--     make_ordinal = function(e) -> string
						--   },
						--   -- for example to disable the custom builtin "codeactions" display
						--      do the following
						--   codeactions = false,
						-- }
					},
				},
			})
			require("telescope").load_extension("ui-select")
			require("telescope").load_extension("fzf")
		end,
	},
}
