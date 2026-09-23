local Config = require("diffbuf.config")
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
  "foldenable",
  "foldexpr",
  "foldlevel",
  "foldmethod",
  "foldtext",
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

---Re-assigning a fold option rebuilds the folds and re-applies 'foldlevel',
---which would reopen what the user or the generated-file collapsing closed. The
---option applies run on every BufEnter, so only write a value that drifted.
local function keep_win_option(win, option, value)
  if vim.api.nvim_get_option_value(option, { win = win, scope = "local" }) ~= value then
    set_win_option(win, option, value)
  end
end

local function set_window_options(win)
  set_win_option(win, "statuscolumn", "%{v:lua.require'diffbuf.ui'.statuscolumn()}")
  set_win_option(win, "number", false)
  set_win_option(win, "relativenumber", false)
  set_win_option(win, "signcolumn", "no")
  set_win_option(win, "wrap", false)
  keep_win_option(win, "foldmethod", "expr")
  keep_win_option(win, "foldexpr", "v:lua.require'diffbuf.ui'.foldexpr()")
  keep_win_option(win, "foldtext", "v:lua.require'diffbuf.ui'.foldtext()")
  keep_win_option(win, "foldenable", true)
end

-- Folds ----------------------------------------------------------------------

---Rows line up one-to-one with buffer lines, but only while a parsed diff is on
---screen: the loading and error messages have no rows behind them.
---@param buf integer
---@return table[]?
local function fold_rows(buf)
  local state = State.get(buf)
  if state == nil or state.status ~= "ready" then
    return nil
  end
  if #state.rows ~= vim.api.nvim_buf_line_count(buf) then
    return nil
  end
  return state.rows
end

---A file opens a level-1 fold and each of its hunks a level-2 fold inside it, so
---`zc` collapses the hunk under the cursor and a second `zc` its whole file.
---@return string
function M.foldexpr()
  local rows = fold_rows(vim.api.nvim_get_current_buf())
  local row = rows ~= nil and rows[vim.v.lnum] or nil
  if row == nil then
    return "0"
  end
  if row.kind == "file" then
    return ">1"
  end
  if row.hunk == true then
    return ">2"
  end
  return "="
end

local function fold_counts(fold, lines)
  local parts = { ("%d line%s"):format(lines, lines == 1 and "" or "s") }
  if fold.added > 0 then
    parts[#parts + 1] = "+" .. fold.added
  end
  if fold.removed > 0 then
    parts[#parts + 1] = "-" .. fold.removed
  end
  return table.concat(parts, " ")
end

---@return string
function M.foldtext()
  local start = vim.v.foldstart
  local lines = vim.v.foldend - start + 1
  local rows = fold_rows(vim.api.nvim_get_current_buf())
  local row = rows ~= nil and rows[start] or nil
  local fold = row ~= nil and row.fold or nil
  -- 'folddashes' carries one dash per level, and a hunk sits one level below its
  -- file.
  local indent = ("  "):rep(math.max(0, #(vim.v.folddashes or "-") - 1))

  if fold == nil then
    return ("%s%s  ⋯ %d lines"):format(indent, vim.fn.getline(start), lines)
  end

  local label
  if fold.kind == "file" then
    label = vim.fn.getline(start)
    if fold.hunks > 0 then
      label = ("%s  %d hunk%s"):format(label, fold.hunks, fold.hunks == 1 and "" or "s")
    end
    if row.generated then
      label = label .. "  (generated)"
    end
  else
    label = fold.header or "@@"
  end

  return ("%s%s  ⋯ %s"):format(indent, label, fold_counts(fold, lines))
end

---Lines starting the fold of a file .gitattributes marks as generated.
---@param buf integer
---@return integer[]
local function generated_lines(buf)
  local lines = {}
  for index, row in ipairs(fold_rows(buf) or {}) do
    if row.kind == "file" and row.generated then
      lines[#lines + 1] = index
    end
  end
  return lines
end

local function fold_command(win, command, lines)
  vim.api.nvim_win_call(win, function()
    for _, line in ipairs(lines) do
      -- A file the diff shows without any hunk has no fold to act on.
      pcall(vim.cmd, line .. command)
    end
  end)
end

local function fold_closed(win, line)
  local ok, closed = pcall(function()
    if win == vim.api.nvim_get_current_win() then
      return vim.fn.foldclosed(line)
    end
    return vim.api.nvim_win_call(win, function()
      return vim.fn.foldclosed(line)
    end)
  end)
  return ok and closed == line
end

---Collapse generated files once per window and render, so the repeated option
---applies behind a BufEnter cannot fight a manual expand. A window that leaves
---the buffer and comes back starts from the collapsed state again.
local function collapse_generated(buf, win)
  local state = State.get(buf)
  local owned = window_states[win]
  local tick = state ~= nil and state.render_tick or 0
  if owned == nil or owned.buf ~= buf or owned.generated_tick == tick then
    return
  end

  owned.generated_tick = tick
  if not Config.get().generated.collapse then
    return
  end
  local lines = generated_lines(buf)
  if #lines > 0 then
    fold_command(win, "foldclose", lines)
  end
end

---Write 'foldlevel' once, when the window takes the buffer over. It belongs to
---the user from then on, so `zR` and `zM` outlive the option applies that follow
---every BufEnter.
local function init_folds(buf, win)
  local owned = window_states[win]
  if owned == nil or owned.buf ~= buf or owned.folds_initialized then
    return
  end
  owned.folds_initialized = true
  set_win_option(win, "foldlevel", 99)
end

---Collapse every generated file, or expand them all when any is collapsed.
---@param buf integer
---@return boolean? collapsed `nil` when the diff holds no generated file
function M.toggle_generated_folds(buf)
  local win = vim.fn.bufwinid(buf)
  local lines = generated_lines(buf)
  if win == -1 or #lines == 0 then
    return nil
  end

  local collapsed = false
  for _, line in ipairs(lines) do
    if fold_closed(win, line) then
      collapsed = true
      break
    end
  end

  fold_command(win, collapsed and "foldopen!" or "foldclose", lines)
  return not collapsed
end

-- Window lifecycle -----------------------------------------------------------

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
  init_folds(buf, win)
  collapse_generated(buf, win)
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

  local state = State.get(buf)
  if state ~= nil then
    state.render_tick = (state.render_tick or 0) + 1
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    collapse_generated(buf, win)
  end
  require("diffbuf.syntax").render(buf)
end

function M.render_error(buf, message)
  replace_lines(buf, { "diffbuf.nvim: " .. message })
  decorate(buf, { { kind = "meta" } })
  require("diffbuf.syntax").clear(buf)
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
  local lnum = row or vim.v.lnum
  local item = state and state.rows[lnum]
  local marker = "  "
  if item ~= nil and item.fold ~= nil then
    marker = fold_closed(win, lnum) and "▸ " or "▾ "
  end
  if item == nil or item.new_line == nil then
    return marker .. "      │ "
  end
  return ("%s%5s │ "):format(marker, item.new_line)
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

  map("gh", function()
    require("diffbuf").generated_toggle()
  end, "Collapse or expand every generated file")

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
