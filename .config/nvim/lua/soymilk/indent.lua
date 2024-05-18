vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "FileType" }, {
	pattern = "*",
	callback = function()
		-- List of web file types
		local filetypes = {
			"html",
			"css",
			"javascript",
			"typescript",
			"jsx",
			"vue",
			"svelte",
			"json",
			"yaml",
			"tsx",
			"astro",
			"pest",
		}
		local found = false

		-- Check if the current filetype is in the web file types list
		for _, ft in ipairs(filetypes) do
			if vim.bo.filetype == ft then
				vim.bo.tabstop = 2
				vim.bo.shiftwidth = 2
				found = true
				break -- Exit loop once a match is found
			end
		end

		if not found then
			vim.bo.tabstop = 4
			vim.bo.shiftwidth = 4
		end
	end,
})
