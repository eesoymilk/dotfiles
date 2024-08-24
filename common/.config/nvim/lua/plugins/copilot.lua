return {
  {
    "zbirenbaum/copilot.lua",
    command = "Copilot",
    event = "InsertEnter",
    opts = {
      panel = { enabled = false },
      suggestion = { enabled = false },
      filetypes = {
        markdown = true,
        gitcommit = true,
      },
    },
  },
  {
    "zbirenbaum/copilot-cmp",
    config = true,
  },
}
