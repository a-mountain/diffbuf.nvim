local Config = require("diffbuf.config")
local Git = require("diffbuf.git")
local Parser = require("diffbuf.parser")
local Review = require("diffbuf.review")
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

  state.job = Git.diff(state.root, state.rev, Config.get().context, function(result)
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

---Open the composite diff buffer. With review mode active and no explicit base,
---it compares against the session base.
---@param opts? diffbuf.OpenOpts
---@return integer?
function M.open(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  vim.validate("opts.cwd", opts.cwd, "string", true)
  vim.validate("opts.base", opts.base, "string", true)

  local session = Review.get()
  local cwd = opts.cwd
  if cwd == nil then
    cwd = (opts.base == nil and session ~= nil) and session.root or vim.uv.cwd()
  end
  local root, root_error = Git.root(cwd)
  if root == nil then
    notify_error(root_error)
    return nil
  end

  local base
  if opts.base == nil and session ~= nil and session.root == root then
    base = { ref = session.ref, commit = session.commit }
  else
    local base_error
    base, base_error =
      Git.resolve_base(root, opts.base or Config.get().review.base, Config.get().review.merge_base)
    if base == nil then
      notify_error(base_error)
      return nil
    end
  end

  local buf = UI.create(root, base.ref)
  local state = State.create(buf, {
    root = root,
    base = base.ref,
    rev = base.commit,
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

  local session = Review.get()
  if session ~= nil and session.root == state.root then
    state.base = session.ref
    state.rev = session.commit
  end
  load(state)
end

---Start review mode, or switch the active session to another base.
---@param opts? diffbuf.ReviewOpts
function M.review(opts)
  return Review.start(opts)
end

---@param opts? diffbuf.ReviewOpts
function M.review_toggle(opts)
  return Review.toggle(opts)
end

function M.review_stop()
  return Review.stop()
end

function M.review_refresh()
  return Review.refresh()
end

---@return diffbuf.Session?
function M.session()
  return Review.get()
end

---Base description for statuslines. Empty when review mode is off.
---@return string
function M.status()
  return Review.status()
end

---Toggle the changed-files panel, starting review mode when needed.
function M.panel_toggle()
  local Panel = require("diffbuf.panel")
  if Panel.is_open() then
    Panel.close()
    return nil
  end
  if not Review.is_active() and Review.start({ panel = false }) == nil then
    return nil
  end
  return Panel.open({ focus = true })
end

---Toggle the inline diff overview, starting review mode when needed.
---@return boolean?
function M.overlay_toggle()
  local Inline = require("diffbuf.inline")
  local started = false
  if not Review.is_active() then
    if Review.start({ panel = false }) == nil then
      return nil
    end
    started = true
  end
  if not Inline.is_enabled() and not Inline.enable() then
    return nil
  end
  if started then
    -- Starting review mode is what the user asked for; do not immediately undo
    -- the overlay it just turned on.
    Inline.set_overlay(true)
    return true
  end
  return Inline.toggle_overlay()
end

---mini.diff source reading reference text from the review base. Only needed to
---wire the source manually; review mode installs it on its own.
---@return table
function M.minidiff_source()
  return require("diffbuf.inline").source()
end

function M.setup(opts)
  Config.setup(opts)
end

return M
