return {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    cond = vim.g.vscode,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
        options = {
            theme = "auto",
        },
        sections = {
            lualine_x = {
                {
                    require("noice").api.statusline.mode.get,
                    cond = require("noice").api.statusline.mode.has,
                    color = { fg = "#ff9e64" },
                },
            },
        },
    },
}
