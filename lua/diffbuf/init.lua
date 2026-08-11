local Config = require("diffbuf.config")
local Git = require("diffbuf.git")
local Parser = require("diffbuf.parser")
local State = require("diffbuf.state")
local UI = require("diffbuf.ui")

local M = {}

local function notify_error(message)
  vim.notify("diffbuf.nvim: " .. message, vim.log.levels.ERROR)
end

local function load(state)
  state.generation = state.generation + 1
  local generation = state.generation
  state.status = "loading"
  vim.b[state.buf].diffbuf_status = "loading"

  if state.job ~= nil then
    pcall(state.job.kill, state.job, "sigterm")
  end

  state.job = Git.diff(state.root, state.base, Config.get().context, function(result)
    local current = State.get(state.buf)
    if current ~= state or state.generation ~= generation then
      return
    end
    state.job = nil
    if not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end

    if result.code ~= 0 then
      state.status = "error"
      vim.b[state.buf].diffbuf_status = "error"
      local message = (result.stderr or ""):gsub("%s+$", "")
      if message == "" then
        message = "git diff failed"
      end
      UI.render_error(state.buf, message)
      notify_error(message)
      return
    end

    local parsed = Parser.parse(result.stdout or "")
    state.rows = parsed.rows
    state.status = "ready"
    vim.b[state.buf].diffbuf_status = "ready"
    UI.render(state.buf, parsed, state.base)
  end)
end

---@class diffbuf.OpenOpts
---@field cwd? string
---@field base? string

---@param opts? diffbuf.OpenOpts
---@return integer?
function M.open(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  vim.validate("opts.cwd", opts.cwd, "string", true)
  vim.validate("opts.base", opts.base, "string", true)

  local cwd = opts.cwd or vim.uv.cwd()
  local root, root_error = Git.root(cwd)
  if root == nil then
    notify_error(root_error)
    return nil
  end

  local base = opts.base
  if base == nil then
    local base_error
    base, base_error = Git.default_branch(root)
    if base == nil then
      notify_error(base_error)
      return nil
    end
  end

  local buf = UI.create(root, base)
  local state = State.create(buf, {
    root = root,
    base = base,
  })
  UI.install_mappings(buf)
  load(state)
  return buf
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local state = State.get(buf)
  if state == nil then
    notify_error("the current buffer is not owned by diffbuf.nvim")
    return
  end
  load(state)
end

function M.setup(opts)
  Config.setup(opts)
end

return M
