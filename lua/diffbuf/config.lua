local M = {}

local defaults = {
  context = 3,
  lsp_attach_timeout_ms = 3000,
  review = {
    -- Base revision. `nil` resolves the repository default branch.
    base = nil,
    -- Compare against the merge base of the review base and HEAD, like a
    -- GitHub pull request does.
    merge_base = true,
    -- Treat untracked files as fully added.
    untracked = true,
    -- Turn on the mini.diff inline diff when review mode starts.
    inline = true,
    -- Start with the mini.diff overlay ("overview") visible. Off by default so
    -- :DiffBufOverlay is what reveals removed lines.
    overlay = false,
    -- Open the changed-files panel when review mode starts.
    panel = true,
  },
  panel = {
    position = "right",
    -- Fractions of 'columns' when <= 1, otherwise a column count.
    width = 0.3,
    layout = "tree",
    -- Join directory chains that hold a single changed subdirectory.
    group_dirs = true,
    -- Move the panel cursor to the entered file.
    follow = true,
    icons = true,
  },
}

local current

local function validate_review(review)
  vim.validate("opts.review", review, "table")
  vim.validate("opts.review.base", review.base, "string", true)
  vim.validate("opts.review.merge_base", review.merge_base, "boolean")
  vim.validate("opts.review.untracked", review.untracked, "boolean")
  vim.validate("opts.review.inline", review.inline, "boolean")
  vim.validate("opts.review.overlay", review.overlay, "boolean")
  vim.validate("opts.review.panel", review.panel, "boolean")
end

local function validate_panel(panel)
  vim.validate("opts.panel", panel, "table")
  vim.validate("opts.panel.position", panel.position, "string")
  vim.validate("opts.panel.width", panel.width, "number")
  vim.validate("opts.panel.layout", panel.layout, "string")
  vim.validate("opts.panel.group_dirs", panel.group_dirs, "boolean")
  vim.validate("opts.panel.follow", panel.follow, "boolean")
  vim.validate("opts.panel.icons", panel.icons, "boolean")

  if panel.position ~= "left" and panel.position ~= "right" then
    error("diffbuf.nvim: opts.panel.position must be 'left' or 'right'")
  end
  if panel.layout ~= "tree" and panel.layout ~= "flat" then
    error("diffbuf.nvim: opts.panel.layout must be 'tree' or 'flat'")
  end
  if panel.width <= 0 then
    error("diffbuf.nvim: opts.panel.width must be positive")
  end
end

local function resolve(user)
  user = user or {}
  vim.validate("opts", user, "table")
  vim.validate("opts.context", user.context, "number", true)
  vim.validate("opts.lsp_attach_timeout_ms", user.lsp_attach_timeout_ms, "number", true)
  vim.validate("opts.review", user.review, "table", true)
  vim.validate("opts.panel", user.panel, "table", true)

  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.deepcopy(user))
  if config.context < 0 or config.context % 1 ~= 0 then
    error("diffbuf.nvim: opts.context must be a non-negative integer")
  end
  if config.lsp_attach_timeout_ms < 0 then
    error("diffbuf.nvim: opts.lsp_attach_timeout_ms must be non-negative")
  end
  validate_review(config.review)
  validate_panel(config.panel)
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
