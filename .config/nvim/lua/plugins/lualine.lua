return {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    cond = vim.g.vscode,
    dependencies = {
        {
            "nvim-tree/nvim-web-devicons",
            lazy = true,
        },
    },
    opts = {
        options = {
            theme = "auto",
        },
    },
    config = function(_, opts)
        require("lualine").setup(opts)
    end,
}

