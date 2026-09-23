if vim.fn.has("nvim-0.13") == 0 then
  vim.notify_once("diffbuf.nvim requires Neovim 0.13+", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_diffbuf then
  return
end
vim.g.loaded_diffbuf = 1

local function complete_revision(arg_lead)
  local root = vim.uv.cwd()
  return vim.tbl_filter(function(ref)
    return vim.startswith(ref, arg_lead)
  end, require("diffbuf.git").refs(root))
end

vim.api.nvim_create_user_command("DiffBufOpen", function(command)
  require("diffbuf").open({
    base = command.args ~= "" and command.args or nil,
  })
end, {
  nargs = "?",
  complete = complete_revision,
  desc = "Open the working-tree diff in one read-only buffer",
})

vim.api.nvim_create_user_command("DiffBufRefresh", function()
  require("diffbuf").refresh()
end, {
  desc = "Refresh the current diffbuf.nvim buffer",
})

vim.api.nvim_create_user_command("DiffBufGenerated", function()
  local hidden = require("diffbuf").generated_toggle()
  if hidden ~= nil then
    vim.notify(
      "diffbuf.nvim: generated changes " .. (hidden and "hidden" or "shown"),
      vim.log.levels.INFO
    )
  end
end, {
  desc = "Collapse or expand the generated files in the composite buffer",
})
