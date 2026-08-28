return {
  "catppuccin/nvim",
  lazy = false,
  name = "catppuccin",
  priority = 1000,
  cond = not vim.g.vscode,
  opts = {
    transparent_background = true,
    integrations = {
      nvimtree = true,
      which_key = true,
    },
    highlight_overrides = {
      mocha = function(mocha)
        return {
          NvimTreeNormal = { bg = mocha.none },
        }
      end,
    },
  },
  config = function(_, opts)
    require("catppuccin").setup(opts)
    -- load the colorscheme here
    vim.cmd([[colorscheme catppuccin-macchiato]])
  end,
}
