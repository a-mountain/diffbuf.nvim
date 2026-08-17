local Config = require("diffbuf.config")
local Git = require("diffbuf.git")
local Review = require("diffbuf.review")

local M = {}

local enabled = false
local overlay = false
local previous_source
local previous_global_disable
local ref_generations = {}
local attached = {}

---mini.diff is an optional dependency: the inline review diff needs it, the
---composite buffer and the panel do not.
---@return table? module
---@return string? error
local function minidiff()
  local ok, module = pcall(require, "mini.diff")
  if not ok then
    return nil, "mini.diff is not installed; install nvim-mini/mini.diff for the inline review diff"
  end
  if module.config == nil then
    return nil, "mini.diff is not set up; call require('mini.diff').setup() in your config"
  end
  return module
end

local function notify(message, level)
  vim.notify("diffbuf.nvim: " .. message, level or vim.log.levels.ERROR)
end

local function eligible(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].buflisted
    and Review.relative(vim.api.nvim_buf_get_name(buf)) ~= nil
end

local function apply_overlay(buf)
  local module = minidiff()
  if module == nil then
    return
  end
  local data = module.get_buf_data(buf)
  if data == nil or data.overlay == overlay then
    return
  end
  pcall(module.toggle_overlay, buf)
end

---Set the buffer's reference text to its content in the review base.
---@param buf integer
function M.load_ref(buf)
  local session = Review.get()
  local module = minidiff()
  if session == nil or module == nil then
    return
  end

  local relative = Review.relative(vim.api.nvim_buf_get_name(buf))
  if relative == nil then
    return
  end

  local generation = (ref_generations[buf] or 0) + 1
  ref_generations[buf] = generation
  local commit = session.commit

  Git.file_at_rev(session.root, commit, Review.base_path(relative), function(result)
    if ref_generations[buf] ~= generation or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local current = Review.get()
    if current == nil or current.commit ~= commit then
      return
    end
    if module.get_buf_data(buf) == nil then
      return
    end

    if result.code ~= 0 then
      -- The path does not exist in the base revision: new or untracked file.
      if Config.get().review.untracked then
        module.set_ref_text(buf, "")
        apply_overlay(buf)
      else
        module.fail_attach(buf)
      end
      return
    end

    module.set_ref_text(buf, result.stdout or "")
    apply_overlay(buf)
  end)
end

---@param buf integer
---@return false? `false` when the buffer is outside the review
function M.attach(buf)
  if Review.get() == nil then
    return false
  end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return false
  end
  if Review.relative(vim.api.nvim_buf_get_name(buf)) == nil then
    return false
  end

  attached[buf] = true
  M.load_ref(buf)
  return nil
end

---mini.diff source that reads reference text from the review base.
---@return table
function M.source()
  return {
    name = "diffbuf-review",
    attach = function(buf)
      return M.attach(buf)
    end,
    detach = function(buf)
      ref_generations[buf] = (ref_generations[buf] or 0) + 1
      attached[buf] = nil
    end,
    apply_hunks = function()
      error("diffbuf.nvim: review hunks are read-only; stop review mode to stage hunks")
    end,
  }
end

---Show the review diff inline in every file of the repository.
---@return boolean
function M.enable()
  local module, module_error = minidiff()
  if module == nil then
    notify(module_error)
    return false
  end

  if not enabled then
    previous_source = module.config.source
    previous_global_disable = vim.g.minidiff_disable
    enabled = true
  end

  -- Files outside the review keep whatever source the user configured, because
  -- this source declines to attach there.
  local sources = { M.source() }
  if previous_source ~= nil then
    if vim.islist(previous_source) then
      vim.list_extend(sources, previous_source)
    else
      sources[#sources + 1] = previous_source
    end
  end
  module.config.source = sources
  vim.g.minidiff_disable = false
  overlay = Config.get().review.overlay

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if eligible(buf) then
      if module.get_buf_data(buf) ~= nil then
        module.disable(buf)
      end
      pcall(module.enable, buf)
    end
  end

  return true
end

function M.disable()
  local module = minidiff()
  local released = {}

  if module ~= nil then
    for _, buf in ipairs(vim.tbl_keys(attached)) do
      if vim.api.nvim_buf_is_valid(buf) and module.get_buf_data(buf) ~= nil then
        module.disable(buf)
        released[#released + 1] = buf
      end
    end
    if enabled then
      module.config.source = previous_source
    end
  end

  if enabled then
    vim.g.minidiff_disable = previous_global_disable
  end

  enabled = false
  overlay = false
  attached = {}
  ref_generations = {}
  previous_source = nil
  previous_global_disable = nil

  -- Hand the released buffers back to the user's own mini.diff configuration.
  if module ~= nil and vim.g.minidiff_disable ~= true then
    for _, buf in ipairs(released) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(module.enable, buf)
      end
    end
  end
end

---Reload reference text after the base commit changed.
function M.refresh()
  if not enabled then
    return
  end
  for _, buf in ipairs(vim.tbl_keys(attached)) do
    if vim.api.nvim_buf_is_valid(buf) then
      M.load_ref(buf)
    end
  end
end

---Attach every eligible buffer that mini.diff has not picked up yet, so a
---buffer loaded while the inline diff was off still takes part.
function M.ensure_attached()
  local module = minidiff()
  if module == nil or not enabled then
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if eligible(buf) and module.get_buf_data(buf) == nil then
      pcall(module.enable, buf)
    end
  end
end

---@param value boolean
function M.set_overlay(value)
  overlay = value
  M.ensure_attached()
  for _, buf in ipairs(vim.tbl_keys(attached)) do
    if vim.api.nvim_buf_is_valid(buf) then
      apply_overlay(buf)
    end
  end
end

---Toggle the deleted-and-changed-lines overview across the whole review.
---@return boolean
function M.toggle_overlay()
  M.set_overlay(not overlay)
  return overlay
end

function M.is_enabled()
  return enabled
end

function M.overlay_enabled()
  return overlay
end

return M
