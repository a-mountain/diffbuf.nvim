local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")

vim.opt.runtimepath:prepend(plugin_root)

-- Optional dependencies checked out by `make deps`.
local deps_dir = vim.env.NVIM_DEPS_DIR
if deps_dir ~= nil and vim.uv.fs_stat(deps_dir) ~= nil then
  for name in vim.fs.dir(deps_dir) do
    vim.opt.runtimepath:prepend(vim.fs.joinpath(deps_dir, name))
  end
end

vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.undofile = false
vim.cmd("filetype plugin indent on")
