return {
  "uga-rosa/ccc.nvim",
  event = "BufReadPre",
  config = function()
    require("ccc").setup({
      highlighter = {
        auto_enable = true,
        lsp = true,
      },
    })
  end,
}
