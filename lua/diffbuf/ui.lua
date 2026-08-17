local State = require("diffbuf.state")

local M = {}
local namespace = vim.api.nvim_create_namespace("diffbuf.nvim")
local window_states = {}
local apply_gens = {}
local runtime_initialized = false

local window_options = {
  "statuscolumn",
  "number",
  "relativenumber",
  "signcolumn",
  "wrap",
}

local highlights = {
  added = "DiffAdd",
  deleted = "DiffDelete",
  file = "DiffBufFile",
  hunk = "DiffBufHunk",
  meta = "DiffBufMeta",
}

local function set_modifiable(buf, value)
  vim.api.nvim_set_option_value("modifiable", value, { buf = buf })
end

local function replace_lines(buf, lines)
  vim.api.nvim_set_option_value("readonly", false, { buf = buf })
  set_modifiable(buf, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  set_modifiable(buf, false)
  vim.api.nvim_set_option_value("readonly", true, { buf = buf })
end

local function decorate(buf, rows)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for index, row in ipairs(rows) do
    local group = highlights[row.kind]
    if group ~= nil then
      vim.api.nvim_buf_set_extmark(buf, namespace, index - 1, 0, {
        line_hl_group = group,
        priority = row.kind == "file" and 120 or 110,
      })
    end
  end
end

local function define_highlights()
  vim.api.nvim_set_hl(0, "DiffBufFile", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "DiffBufHunk", { default = true, link = "DiffText" })
  vim.api.nvim_set_hl(0, "DiffBufMeta", { default = true, link = "Comment" })
end

local function snapshot_window(win)
  local previous = {}
  for _, option in ipairs(window_options) do
    previous[option] = vim.api.nvim_get_option_value(option, { win = win, scope = "local" })
  end
  return previous
end

local global_defaults

local function remember_globals()
  if global_defaults ~= nil then
    return
  end
  global_defaults = {}
  for _, option in ipairs(window_options) do
    global_defaults[option] = vim.api.nvim_get_option_value(option, { scope = "global" })
  end
end

local function unpoison_globals()
  if global_defaults == nil then
    return
  end
  local statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { scope = "global" })
  if type(statuscolumn) ~= "string" or not statuscolumn:find("diffbuf.ui", 1, true) then
    return
  end
  for option, value in pairs(global_defaults) do
    vim.api.nvim_set_option_value(option, value, { scope = "global" })
  end
end

local function set_win_option(win, option, value)
  vim.api.nvim_set_option_value(option, value, { win = win, scope = "local" })
end

local function set_window_options(win)
  set_win_option(win, "statuscolumn", "%{v:lua.require'diffbuf.ui'.statuscolumn()}")
  set_win_option(win, "number", false)
  set_win_option(win, "relativenumber", false)
  set_win_option(win, "signcolumn", "no")
  set_win_option(win, "wrap", false)
end

local function restore_window(win, buf)
  local owned = window_states[win]
  if owned == nil or owned.buf ~= buf or not vim.api.nvim_win_is_valid(win) then
    return
  end
  apply_gens[win] = (apply_gens[win] or 0) + 1
  for option, value in pairs(owned.previous) do
    set_win_option(win, option, value)
  end
  unpoison_globals()
  window_states[win] = nil
end

local function restore_buf_windows(buf)
  local wins = {}
  for win, owned in pairs(window_states) do
    if owned.buf == buf then
      wins[#wins + 1] = win
    end
  end
  for _, win in ipairs(wins) do
    restore_window(win, buf)
  end
end

local function apply_window(buf, win)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end

  local existing = window_states[win]
  if existing ~= nil and existing.buf ~= buf then
    restore_window(win, existing.buf)
    existing = nil
  end

  remember_globals()

  if existing == nil then
    window_states[win] = { buf = buf, previous = snapshot_window(win) }
  end

  set_window_options(win)
end

local function schedule_apply(buf, win)
  local gen = (apply_gens[win] or 0) + 1
  apply_gens[win] = gen
  vim.schedule(function()
    if apply_gens[win] ~= gen then
      return
    end
    apply_window(buf, win)
  end)
end

local function ensure_runtime()
  if runtime_initialized then
    return
  end
  runtime_initialized = true

  local group = vim.api.nvim_create_augroup("DiffBufUi", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    desc = "Release diffbuf.nvim window state",
    callback = function(event)
      local win = tonumber(event.match)
      if win ~= nil then
        apply_gens[win] = (apply_gens[win] or 0) + 1
        window_states[win] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "BufEnter" }, {
    group = group,
    desc = "Restore diffbuf.nvim window options when another buffer is shown",
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local owned = window_states[win]
      if owned ~= nil and owned.buf ~= vim.api.nvim_win_get_buf(win) then
        restore_window(win, owned.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "Restore diffbuf.nvim highlight links",
    callback = define_highlights,
  })
end

function M.create(root, base)
  ensure_runtime()
  define_highlights()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, ("diffbuf://%s@%s#%d"):format(root, base, buf))

  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("buflisted", true, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("undolevels", -1, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = buf })

  replace_lines(buf, { ("Loading diff against %s…"):format(base) })
  vim.api.nvim_set_option_value("filetype", "diffbuf", { buf = buf })

  local win = vim.api.nvim_get_current_win()
  window_states[win] = { buf = buf, previous = snapshot_window(win) }
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, {
    buffer = buf,
    desc = "Apply diffbuf.nvim window options",
    callback = function()
      local current_win = vim.api.nvim_get_current_win()
      apply_window(buf, current_win)
      schedule_apply(buf, current_win)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinLeave", "BufLeave" }, {
    buffer = buf,
    desc = "Restore options owned by diffbuf.nvim",
    callback = function()
      restore_buf_windows(buf)
    end,
  })
  apply_window(buf, win)
  schedule_apply(buf, win)

  return buf
end

function M.render(buf, parsed, base)
  local lines = parsed.lines
  local rows = parsed.rows
  if #lines == 0 then
    lines = { ("No changes against %s"):format(base) }
    rows = { { kind = "meta" } }
  end
  replace_lines(buf, lines)
  decorate(buf, rows)
  vim.api.nvim_set_option_value("modified", false, { buf = buf })
end

function M.render_error(buf, message)
  replace_lines(buf, { "diffbuf.nvim: " .. message })
  decorate(buf, { { kind = "meta" } })
end

function M.statuscolumn(row)
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return ""
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= "diffbuf" then
    return ""
  end
  local state = State.get(buf)
  local item = state and state.rows[row or vim.v.lnum]
  if item == nil or item.new_line == nil then
    return "      │ "
  end
  return ("%5s │ "):format(item.new_line)
end

function M.install_mappings(buf)
  local function map(lhs, callback, description)
    vim.keymap.set("n", lhs, callback, {
      buffer = buf,
      silent = true,
      desc = description,
    })
  end

  map("gd", function()
    require("diffbuf.lsp").definition(buf)
  end, "Go to definition from the source location")

  map("<CR>", function()
    require("diffbuf.actions").open_source(buf)
  end, "Open the source location")

  map("]f", function()
    require("diffbuf.actions").navigate(buf, "file", 1)
  end, "Next changed file")
  map("[f", function()
    require("diffbuf.actions").navigate(buf, "file", -1)
  end, "Previous changed file")
  map("]c", function()
    require("diffbuf.actions").navigate(buf, "hunk", 1)
  end, "Next diff hunk")
  map("[c", function()
    require("diffbuf.actions").navigate(buf, "hunk", -1)
  end, "Previous diff hunk")

  map("r", function()
    require("diffbuf").refresh(buf)
  end, "Refresh the diff")

  map("q", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, "Close the diff")

  map("?", function()
    vim.cmd("help diffbuf")
  end, "Show diffbuf.nvim help")
end

M.namespace = namespace
return M
