if vim.fn.has("nvim-0.13") == 0 then
  vim.notify_once("diffbuf.nvim requires Neovim 0.13+", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_diffbuf then
  return
end
vim.g.loaded_diffbuf = 1

vim.api.nvim_create_user_command("DiffBufOpen", function(command)
  require("diffbuf").open({
    base = command.args ~= "" and command.args or nil,
  })
end, {
  nargs = "?",
  desc = "Open the working-tree diff in one read-only buffer",
})

vim.api.nvim_create_user_command("DiffBufRefresh", function()
  require("diffbuf").refresh()
end, {
  desc = "Refresh the current diffbuf.nvim buffer",
})
