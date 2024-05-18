return {
    'nvim-telescope/telescope.nvim', tag = '0.1.4',
    cond = vim.g.vscode,
    dependencies = {
        'nvim-lua/plenary.nvim',
        'BurntSushi/ripgrep',   -- ripgrep binary also needs to be installed
    },
    keys = {
        {
            "<leader>ff",
            function ()
                require("telescope.builtin").find_files()
            end,
            desc = "Find project files",
        },
        {
            "<leader>gf",
            function ()
                require("telescope.builtin").git_files()
            end,
            desc = "Find git files",
        },
        {
            "<leader>lg",
            function ()
                require("telescope.builtin").live_grep()
            end,
            desc = "Search for a string in your current working directory lively",
        },
    },
    config = function ()
        require("telescope").setup()
    end,
}
