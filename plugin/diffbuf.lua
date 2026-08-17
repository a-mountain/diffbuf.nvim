if vim.fn.has("nvim-0.13") == 0 then
  vim.notify_once("diffbuf.nvim requires Neovim 0.13+", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_diffbuf then
  return
end
vim.g.loaded_diffbuf = 1

local function complete_revision(arg_lead)
  local session = require("diffbuf.review").get()
  local root = session ~= nil and session.root or vim.uv.cwd()
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

vim.api.nvim_create_user_command("DiffBufReview", function(command)
  require("diffbuf").review({
    base = command.args ~= "" and command.args or nil,
  })
end, {
  nargs = "?",
  complete = complete_revision,
  desc = "Start review mode against a base revision",
})

vim.api.nvim_create_user_command("DiffBufReviewToggle", function(command)
  require("diffbuf").review_toggle({
    base = command.args ~= "" and command.args or nil,
  })
end, {
  nargs = "?",
  complete = complete_revision,
  desc = "Toggle review mode",
})

vim.api.nvim_create_user_command("DiffBufReviewStop", function()
  require("diffbuf").review_stop()
end, {
  desc = "Stop review mode and release every review surface",
})

vim.api.nvim_create_user_command("DiffBufReviewRefresh", function()
  require("diffbuf").review_refresh()
end, {
  desc = "Re-resolve the review base and reload every review surface",
})

vim.api.nvim_create_user_command("DiffBufPanel", function()
  require("diffbuf").panel_toggle()
end, {
  desc = "Toggle the changed-files panel",
})

vim.api.nvim_create_user_command("DiffBufOverlay", function()
  -- Files with additions only look the same either way, so say what happened.
  local shown = require("diffbuf").overlay_toggle()
  if shown ~= nil then
    vim.notify("diffbuf.nvim: review overview " .. (shown and "on" or "off"), vim.log.levels.INFO)
  end
end, {
  desc = "Toggle the inline diff overview in every reviewed file",
})
