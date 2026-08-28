-- Spell checking configuration
-- Auto-enable spell checking for specific file types

-- Enable spell checking for tex and typst files
-- (markdown excluded: undercurls on code identifiers are too noisy; toggle with <leader>ts)
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "tex", "plaintex", "typst" },
	callback = function()
		vim.opt_local.spell = true
		vim.opt_local.spelllang = "en_us"
	end,
	desc = "Enable spell checking for document files",
})

-- Toggle spell checking on demand
vim.keymap.set("n", "<leader>ts", function()
	vim.opt_local.spell = not vim.opt_local.spell:get()
	vim.opt_local.spelllang = "en_us"
end, { desc = "Toggle spell checking" })

