return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  cond = not vim.g.vscode,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    { "antosha417/nvim-lsp-file-operations", config = true },
  },
  keys = {
    {
      "<leader>n",
      function()
        require("nvim-tree.api").tree.toggle({ find_file = true })
      end,
      desc = "Toggle Nvim Tree",
    },
  },
  opts = {
    tab = {
      sync = {
        open = true,
        close = true,
      },
    },
    actions = {
      open_file = {
        quit_on_open = true,
      },
    },
  },
}
