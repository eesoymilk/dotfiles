return {
    'nvim-treesitter/nvim-treesitter-context',
    enabled = true,
    events = { 'BufEnter' },
    opts = {
        multiline_threshold = 1,
    },
    config = true,
}
