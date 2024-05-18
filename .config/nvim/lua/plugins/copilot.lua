return {
    'github/copilot.vim',
    command = 'Copilot',
    events = 'BufEnter',
    config = function()
        vim.cmd('Copilot setup')
    end,
}
