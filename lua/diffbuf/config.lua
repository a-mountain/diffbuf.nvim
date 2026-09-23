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
  -- Base revision. `nil` resolves the repository default branch.
  base = nil,
  -- Compare against the merge base of the base revision and HEAD, like a
  -- GitHub pull request does.
  merge_base = true,
  generated = {
    -- .gitattributes attributes that mark a file as generated. GitHub reads
    -- `linguist-generated`, GitLab reads `gitlab-generated`. An empty list
    -- turns the detection off.
    attributes = { "linguist-generated", "gitlab-generated" },
    -- Start generated files collapsed in the composite buffer.
    collapse = true,
    -- Move generated files behind everything else in the composite buffer.
    sort_last = true,
  },
}

local current

local function validate_generated(generated)
  vim.validate("opts.generated", generated, "table")
  vim.validate("opts.generated.attributes", generated.attributes, "table")
  vim.validate("opts.generated.collapse", generated.collapse, "boolean")
  vim.validate("opts.generated.sort_last", generated.sort_last, "boolean")

  for _, attribute in ipairs(generated.attributes) do
    if type(attribute) ~= "string" or attribute == "" then
      error("diffbuf.nvim: opts.generated.attributes must be a list of attribute names")
    end
  end
end

local function resolve(user)
  user = user or {}
  vim.validate("opts", user, "table")
  vim.validate("opts.context", user.context, "number", true)
  vim.validate("opts.lsp_attach_timeout_ms", user.lsp_attach_timeout_ms, "number", true)
  vim.validate("opts.syntax", user.syntax, "boolean", true)
  vim.validate("opts.filetypes", user.filetypes, "table", true)
  vim.validate("opts.base", user.base, "string", true)
  vim.validate("opts.merge_base", user.merge_base, "boolean", true)
  vim.validate("opts.generated", user.generated, "table", true)

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
  validate_generated(config.generated)
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
