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
end

return M
