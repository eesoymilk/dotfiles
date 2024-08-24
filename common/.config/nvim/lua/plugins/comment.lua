return {
  "JoosepAlviste/nvim-ts-context-commentstring",
  {
    "numToStr/Comment.nvim",
    opts = {
      pre_hook = function()
        return vim.bo.commentstring
      end,
    },
  },
}
