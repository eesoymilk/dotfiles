return {
  "stevearc/oil.nvim",
  lazy = false,
  cond = not vim.g.vscode,
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
  },
  opts = {
    view_options = { show_hidden = true },
  },
}
