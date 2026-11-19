return {
  "tpope/vim-fugitive",
  cmd = { "Git", "G", "Gedit", "Gdiffsplit", "Gvdiffsplit" },
  keys = {
    { "<leader>gb", "<cmd>Git blame<cr>", desc = "Git blame (interactive)" },
    { "<leader>gd", "<cmd>Gvdiffsplit<cr>", desc = "Diff against staging area" },
  },
}
