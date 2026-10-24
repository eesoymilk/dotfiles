-- On Omarchy, follow the system theme. Each Omarchy theme ships a LazyVim-style
-- spec: the colorscheme plugin(s) plus a "LazyVim/LazyVim" entry naming the
-- colorscheme. This config is plain lazy.nvim, so take the plugins as-is and
-- read the name out of the LazyVim entry. Elsewhere, Catppuccin.
local omarchy_theme = vim.fn.expand("~/.local/state/omarchy/current/theme/neovim.lua")

local colorscheme = "catppuccin-macchiato"
local specs = {
	{
		"catppuccin/nvim",
		lazy = false,
		name = "catppuccin",
		priority = 1000,
		cond = not vim.g.vscode,
		opts = {
			transparent_background = true,
			integrations = {
				nvimtree = true,
				which_key = true,
			},
			highlight_overrides = {
				mocha = function(mocha)
					return {
						NvimTreeNormal = { bg = mocha.none },
					}
				end,
			},
		},
	},
}

if vim.uv.fs_stat(omarchy_theme) then
	local ok, theme = pcall(dofile, omarchy_theme)
	if ok and type(theme) == "table" then
		for _, spec in ipairs(theme) do
			if spec[1] == "LazyVim/LazyVim" then
				colorscheme = vim.tbl_get(spec, "opts", "colorscheme") or colorscheme
			elseif spec[1] ~= "catppuccin/nvim" then
				table.insert(specs, vim.tbl_extend("force", spec, { lazy = false, priority = 1000 }))
			end
		end
	end
end

-- Apply once every start plugin is loaded, so the theme plugin is on the rtp.
vim.api.nvim_create_autocmd("User", {
	pattern = "LazyDone",
	once = true,
	callback = function()
		if vim.g.vscode then
			return
		end
		if not pcall(vim.cmd.colorscheme, colorscheme) then
			pcall(vim.cmd.colorscheme, "catppuccin-macchiato")
		end
	end,
})

return specs
