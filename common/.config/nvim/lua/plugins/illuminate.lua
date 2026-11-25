return {
  "RRethy/vim-illuminate",
  event = { "BufReadPost", "BufNewFile" },
  cond = not vim.g.vscode,
  config = function()
    require("illuminate").configure({
      -- Under this many lines, everything runs; above it, only the LSP
      -- provider, since regex scans of huge files stall the cursor.
      large_file_cutoff = 2000,
      large_file_overrides = { providers = { "lsp" } },
    })
  end,
}
