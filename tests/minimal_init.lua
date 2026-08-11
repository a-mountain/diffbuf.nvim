local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")

vim.opt.runtimepath:prepend(plugin_root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.undofile = false
vim.cmd("filetype plugin indent on")
