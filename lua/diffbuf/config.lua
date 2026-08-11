local M = {}

local defaults = {
  context = 3,
  lsp_attach_timeout_ms = 3000,
}

local current

local function resolve(user)
  user = user or {}
  vim.validate("opts", user, "table")
  vim.validate("opts.context", user.context, "number", true)
  vim.validate("opts.lsp_attach_timeout_ms", user.lsp_attach_timeout_ms, "number", true)

  local config = vim.tbl_extend("force", defaults, user)
  if config.context < 0 or config.context % 1 ~= 0 then
    error("diffbuf.nvim: opts.context must be a non-negative integer")
  end
  if config.lsp_attach_timeout_ms < 0 then
    error("diffbuf.nvim: opts.lsp_attach_timeout_ms must be non-negative")
  end
  return config
end

function M.setup(user)
  current = resolve(user)
end

function M.get()
  if current == nil then
    current = resolve()
  end
  return current
end

return M
