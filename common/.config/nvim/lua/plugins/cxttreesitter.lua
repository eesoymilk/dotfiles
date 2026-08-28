return {
    'nvim-treesitter/nvim-treesitter-context',
    enabled = true,
    event = { 'BufEnter' },
    opts = {
        multiline_threshold = 1,
    },
    config = true,
}
