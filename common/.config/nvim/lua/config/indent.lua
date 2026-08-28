vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    -- List of file types that use 2-space indentation
    local two_space_filetypes = {
      "html",
      "css",
      "javascript",
      "typescript",
      "jsx",
      "vue",
      "svelte",
      "json",
      "jsonc",
      "yaml",
      "lua",
      "typescriptreact",
      "astro",
      "pest",
      "typst",
    }

    local is_two_space = false
    for _, ft in ipairs(two_space_filetypes) do
      if vim.bo.filetype == ft then
        is_two_space = true
        break
      end
    end

    if is_two_space then
      vim.bo.tabstop = 2
      vim.bo.shiftwidth = 2
      vim.bo.softtabstop = 2
    else
      vim.bo.tabstop = 4
      vim.bo.shiftwidth = 4
      vim.bo.softtabstop = 4
    end
  end,
})
