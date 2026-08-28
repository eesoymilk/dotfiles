-- nvim-treesitter main branch (full rewrite; master is archived and breaks
-- on Neovim 0.12). The plugin now only installs parsers and queries;
-- highlighting and indentation are wired to core Neovim per buffer below.
-- Requires the tree-sitter CLI, installed by bootstrap.sh.
local languages = {
  "bash",
  "c",
  "cpp",
  "css",
  "go",
  "html",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "regex",
  "rust",
  "svelte",
  "tsx",
  "typescript",
  "vim",
  "yaml",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  build = ":TSUpdate",
  cond = not vim.g.vscode,
  lazy = false, -- the main branch does not support lazy-loading
  config = function()
    local ts = require("nvim-treesitter")
    ts.install(languages)

    local function attach(buf, lang)
      if pcall(vim.treesitter.start, buf, lang) then
        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("treesitter_attach", {}),
      callback = function(ev)
        local lang = vim.treesitter.language.get_lang(ev.match)
        -- latex stays out: its parser must be generated from grammar, and
        -- vimtex highlights tex with its own syntax engine anyway.
        if not lang or lang == "latex" then
          return
        end
        if vim.tbl_contains(ts.get_installed(), lang) then
          attach(ev.buf, lang)
        elseif vim.tbl_contains(ts.get_available(), lang) then
          -- auto-install a missing parser, then attach if the buffer is
          -- still around showing the same filetype
          ts.install(lang):await(function()
            if vim.api.nvim_buf_is_valid(ev.buf) and vim.bo[ev.buf].filetype == ev.match then
              attach(ev.buf, lang)
            end
          end)
        end
      end,
    })
  end,
}
