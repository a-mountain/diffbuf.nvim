local M = {}

function M.check()
  vim.health.start("diffbuf.nvim")
  if vim.fn.has("nvim-0.13") == 1 then
    vim.health.ok("Neovim 0.13+ is available")
  else
    vim.health.error("Neovim 0.13+ is required")
  end

  if vim.fn.executable("git") == 1 then
    vim.health.ok("Git is available")
  else
    vim.health.error("Git is required; install it and ensure it is on PATH")
  end

  local ok, minidiff = pcall(require, "mini.diff")
  if not ok then
    vim.health.warn(
      "mini.diff is not installed",
      "install nvim-mini/mini.diff for the inline review diff; the composite buffer and the panel work without it"
    )
  elseif minidiff.config == nil then
    vim.health.warn(
      "mini.diff is installed but not set up",
      "call require('mini.diff').setup() so review mode can install its source"
    )
  else
    vim.health.ok("mini.diff is available for the inline review diff")
  end

  if pcall(require, "mini.icons") then
    vim.health.ok("mini.icons provides panel file icons")
  else
    vim.health.info("mini.icons is not installed; the panel renders without file icons")
  end

  local session = require("diffbuf.review").get()
  if session == nil then
    vim.health.info("review mode is off")
  else
    vim.health.info(("review mode compares %s against %s"):format(session.root, session.commit))
  end
end

return M
