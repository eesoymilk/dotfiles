-- Leader keys must be set before any keymaps or lazy.setup
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("config.remap")
require("config.set")
require("config.indent")
require("config.lazy")
require("config.spell")
