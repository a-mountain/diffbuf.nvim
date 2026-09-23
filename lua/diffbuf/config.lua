local M = {}

local defaults = {
  context = 3,
  lsp_attach_timeout_ms = 3000,
  -- Highlight the composite buffer per file: Tree-sitter where a parser is
  -- installed, Vim's own syntax engine everywhere else.
  syntax = true,
  -- Filetype rules for paths Neovim cannot name, which a diff runs into far
  -- more often than an editing session does. Takes `vim.filetype.add()` form
  -- and is handed straight to it, so it applies to real files too.
  filetypes = {},
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
  generated = {
    -- .gitattributes attributes that mark a file as generated. GitHub reads
    -- `linguist-generated`, GitLab reads `gitlab-generated`. An empty list turns
    -- the detection off.
    attributes = { "linguist-generated", "gitlab-generated" },
    -- Start generated files collapsed in the composite buffer.
    collapse = true,
    -- Move generated files behind everything else in the composite buffer.
    sort_last = true,
    -- Leave generated files out of the changed-files panel.
    hide_in_panel = true,
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

local function validate_generated(generated)
  vim.validate("opts.generated", generated, "table")
  vim.validate("opts.generated.attributes", generated.attributes, "table")
  vim.validate("opts.generated.collapse", generated.collapse, "boolean")
  vim.validate("opts.generated.sort_last", generated.sort_last, "boolean")
  vim.validate("opts.generated.hide_in_panel", generated.hide_in_panel, "boolean")

  for _, attribute in ipairs(generated.attributes) do
    if type(attribute) ~= "string" or attribute == "" then
      error("diffbuf.nvim: opts.generated.attributes must be a list of attribute names")
    end
  end
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
  vim.validate("opts.syntax", user.syntax, "boolean", true)
  vim.validate("opts.filetypes", user.filetypes, "table", true)
  vim.validate("opts.review", user.review, "table", true)
  vim.validate("opts.generated", user.generated, "table", true)
  vim.validate("opts.panel", user.panel, "table", true)

  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.deepcopy(user))
  -- A user list replaces the defaults instead of merging with them, so removing
  -- an attribute is possible.
  if user.generated ~= nil and user.generated.attributes ~= nil then
    config.generated.attributes = vim.deepcopy(user.generated.attributes)
  end
  if config.context < 0 or config.context % 1 ~= 0 then
    error("diffbuf.nvim: opts.context must be a non-negative integer")
  end
  if config.lsp_attach_timeout_ms < 0 then
    error("diffbuf.nvim: opts.lsp_attach_timeout_ms must be non-negative")
  end
  validate_review(config.review)
  validate_generated(config.generated)
  validate_panel(config.panel)
  return config
end

function M.setup(user)
  current = resolve(user)
  if next(current.filetypes) ~= nil then
    vim.filetype.add(current.filetypes)
  end
end

function M.get()
  if current == nil then
    current = resolve()
  end
  return current
end

return M
