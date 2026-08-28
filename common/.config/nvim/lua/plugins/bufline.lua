return {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons", "catppuccin" },
    event = "BufWinEnter",
    keys = {
        {
            "<leader>bl",
            function()
                vim.cmd("BufferLineCycleNext")
            end,
            desc = "Next buffer",
        },
        {
            "<leader>bh",
            function()
                vim.cmd("BufferLineCyclePrev")
            end,
            desc = "Previous buffer",
        },
        {
            "<leader>bc",
            function()
                vim.cmd("BufferLineCloseOthers")
            end,
            desc = "Close other buffers",
        },
    },
    opts = function()
        return {
            highlights = require("catppuccin.special.bufferline").get_theme(),
            options = {
                separator_style = "padded_slant",
                offsets = {
                    {
                        filetype = "NvimTree",
                        text = "File Explorer",
                        text_align = "center",
                        separator = true,
                    },
                },
                hover = {
                    endable = true,
                    delay = 200,
                    reveal = { "close" },
                },
            },
        }
    end,
}
