return {
  "MeanderingProgrammer/render-markdown.nvim",
  cond = not vim.g.vscode,
  dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
  ft = { "markdown" },
  keys = {
    { "<leader>tm", "<cmd>RenderMarkdown toggle<CR>", desc = "Toggle markdown rendering" },
  },
  opts = {},
}
