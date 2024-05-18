return {
    "catppuccin/nvim",
    lazy = false,
    name = "catppuccin",
    priority = 1000,
    cond = vim.g.vscode,
    opts = {
        transparent_background = true,
        integrations = {
            nvimtree = true,
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
