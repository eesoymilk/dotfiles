return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  cond = vim.g.vscode,
  dependencies = {},
  event = { "BufEnter" },
  cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
  opts = {
    highlight = { enable = true },
    indent = { enable = true },
    auto_install = true,
    autotag = { enable = true },
    ensure_installed = {
      "bash",
      "c",
      "cpp",
      "html",
      "javascript",
      "svelte",
      "css",
      "json",
      "lua",
      "markdown",
      "markdown_inline",
      "python",
      "query",
      "regex",
      "rust",
      "tsx",
      "typescript",
      "go",
      "yaml",
      "vim",
    },
  },
  config = function(_, opts)
    if type(opts.ensure_installed) == "table" then
      ---@type table<string, boolean>
      local added = {}
      opts.ensure_installed = vim.tbl_filter(function(lang)
        if added[lang] then
          return false
        end
        added[lang] = true
        return true
      end, opts.ensure_installed)
    end
    require("nvim-treesitter.configs").setup(opts)
  end,
}
