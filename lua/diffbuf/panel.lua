local Config = require("diffbuf.config")
local Git = require("diffbuf.git")
local Review = require("diffbuf.review")
local Tree = require("diffbuf.tree")

local M = {}

local namespace = vim.api.nvim_create_namespace("diffbuf.panel")
local header_height = 3

local state = {
  buf = nil,
  win = nil,
  layout = nil,
  collapsed = {},
  rows = {},
}
local group

local status_labels = {
  A = "added",
  C = "copied",
  D = "deleted",
  M = "modified",
  R = "renamed",
  T = "retyped",
  U = "unmerged",
  ["?"] = "untracked",
}

local status_highlights = {
  A = "DiffBufPanelAdded",
  C = "DiffBufPanelRenamed",
  D = "DiffBufPanelDeleted",
  M = "DiffBufPanelModified",
  R = "DiffBufPanelRenamed",
  T = "DiffBufPanelModified",
  U = "DiffBufPanelModified",
  ["?"] = "DiffBufPanelUntracked",
}

local function define_highlights()
  local links = {
    DiffBufPanelHeader = "Title",
    DiffBufPanelBase = "Special",
    DiffBufPanelInfo = "Comment",
    DiffBufPanelDir = "Directory",
    DiffBufPanelAdded = "Added",
    DiffBufPanelModified = "Changed",
    DiffBufPanelDeleted = "Removed",
    DiffBufPanelRenamed = "Special",
    DiffBufPanelUntracked = "Comment",
    DiffBufPanelCount = "NonText",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

local function notify(message, level)
  vim.notify("diffbuf.nvim: " .. message, level or vim.log.levels.INFO)
end

local function icons()
  if not Config.get().panel.icons then
    return nil
  end
  local ok, module = pcall(require, "mini.icons")
  if not ok then
    return nil
  end
  return module
end

local function file_icon(name)
  local module = icons()
  if module == nil then
    return nil, nil
  end
  local icon, highlight = module.get("file", name)
  return icon, highlight
end

local function is_valid()
  return state.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.win ~= nil
    and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_buf(state.win) == state.buf
end

function M.is_open()
  return is_valid()
end

---@return integer? panel window
function M.win()
  return is_valid() and state.win or nil
end

local function layout()
  if state.layout == nil then
    state.layout = Config.get().panel.layout
  end
  return state.layout
end

-- Rendering ------------------------------------------------------------------

local function counts_virt_text(row)
  local chunks = {}
  local entry = row.entry
  if entry ~= nil then
    local status = entry.status
    chunks[#chunks + 1] = { status .. " ", status_highlights[status] or "DiffBufPanelCount" }
  end
  if entry ~= nil and entry.binary then
    chunks[#chunks + 1] = { "bin", "DiffBufPanelCount" }
  else
    if row.added > 0 then
      chunks[#chunks + 1] = { "+" .. row.added .. " ", "DiffBufPanelAdded" }
    end
    if row.removed > 0 then
      chunks[#chunks + 1] = { "-" .. row.removed, "DiffBufPanelDeleted" }
    end
  end
  if #chunks == 0 then
    return nil
  end
  chunks[#chunks + 1] = { " " }
  return chunks
end

local function row_segments(row)
  local segments = { { string.rep("  ", row.depth) } }

  if row.kind == "dir" then
    segments[#segments + 1] = { row.collapsed and "▸ " or "▾ " }
    segments[#segments + 1] = { row.label, "DiffBufPanelDir" }
    return segments
  end

  local icon, icon_highlight = file_icon(row.label)
  segments[#segments + 1] = { icon ~= nil and (icon .. " ") or "  ", icon_highlight }
  segments[#segments + 1] = {
    row.label,
    status_highlights[row.entry.status] or "DiffBufPanelModified",
  }
  if row.entry.old_path ~= nil then
    segments[#segments + 1] = { " ← " .. row.entry.old_path, "DiffBufPanelInfo" }
  end
  return segments
end

local function header_lines(session, entries)
  local added, removed = 0, 0
  for _, entry in ipairs(entries) do
    added = added + (entry.added or 0)
    removed = removed + (entry.removed or 0)
  end

  local summary
  if session == nil then
    summary = "review mode is off"
  elseif session.files == nil then
    summary = session.files_error or "loading…"
  else
    summary = ("%d file%s  +%d  -%d"):format(#entries, #entries == 1 and "" or "s", added, removed)
  end

  local base = session ~= nil and Review.status() or ""
  local detail = session ~= nil and session.diverged and " (merge base)" or ""

  return {
    {
      { "Review  ", "DiffBufPanelHeader" },
      { base, "DiffBufPanelBase" },
      { detail, "DiffBufPanelCount" },
    },
    { { summary, "DiffBufPanelInfo" }, { "  [" .. layout() .. "]", "DiffBufPanelCount" } },
    {},
  }
end

local function apply_segments(lines, marks, segments)
  local text = {}
  local column = 0
  local row = #lines
  for _, segment in ipairs(segments) do
    local chunk = segment[1]
    if segment[2] ~= nil and chunk ~= "" then
      marks[#marks + 1] = {
        row = row,
        col = column,
        opts = { end_col = column + #chunk, hl_group = segment[2] },
      }
    end
    text[#text + 1] = chunk
    column = column + #chunk
  end
  lines[#lines + 1] = table.concat(text)
end

local function render()
  if not is_valid() then
    return
  end

  local session = Review.get()
  local entries = (session ~= nil and session.files) or {}
  state.rows = Tree.rows(entries, {
    layout = layout(),
    collapsed = state.collapsed,
    group_dirs = Config.get().panel.group_dirs,
  })

  local lines, marks = {}, {}
  for _, segments in ipairs(header_lines(session, entries)) do
    apply_segments(lines, marks, segments)
  end

  if #state.rows == 0 then
    apply_segments(lines, marks, {
      { "  " },
      {
        session == nil and "Start review mode with :DiffBufReview" or "No changes against the base",
        "DiffBufPanelInfo",
      },
    })
  end

  for _, row in ipairs(state.rows) do
    apply_segments(lines, marks, row_segments(row))
    local chunks = counts_virt_text(row)
    if chunks ~= nil then
      marks[#marks + 1] = {
        row = #lines - 1,
        col = 0,
        opts = { virt_text = chunks, virt_text_pos = "right_align", hl_mode = "combine" },
      }
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  for _, mark in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, namespace, mark.row, mark.col, mark.opts)
  end
end

-- Row lookup -----------------------------------------------------------------

---@param lnum? integer 1-based panel line
---@return diffbuf.Row?
function M.row_at(lnum)
  if not is_valid() then
    return nil
  end
  lnum = lnum or vim.api.nvim_win_get_cursor(state.win)[1]
  return state.rows[lnum - header_height]
end

local function line_of(path)
  for index, row in ipairs(state.rows) do
    if row.kind == "file" and row.path == path then
      return index + header_height
    end
  end
  return nil
end

-- Actions --------------------------------------------------------------------

local function target_window()
  local candidates = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local config = vim.api.nvim_win_get_config(win)
    if win ~= state.win and (config.relative == nil or config.relative == "") then
      candidates[#candidates + 1] = win
    end
  end

  local previous = vim.fn.win_getid(vim.fn.winnr("#"))
  if vim.tbl_contains(candidates, previous) then
    return previous
  end
  if #candidates > 0 then
    return candidates[1]
  end

  return vim.api.nvim_open_win(vim.api.nvim_create_buf(true, false), false, {
    split = Config.get().panel.position == "right" and "left" or "right",
    win = state.win,
  })
end

local function jump_to_first_hunk(win, buf)
  local ok, module = pcall(require, "mini.diff")
  if not ok or module.config == nil then
    return
  end

  local function jump()
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
      return true
    end
    local data = module.get_buf_data(buf)
    if data == nil or #data.hunks == 0 then
      return false
    end
    if vim.api.nvim_win_get_cursor(win)[1] ~= 1 then
      return true
    end
    local line = math.max(1, math.min(data.hunks[1].buf_start, vim.api.nvim_buf_line_count(buf)))
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)
    return true
  end

  if jump() then
    return
  end

  local id
  id = vim.api.nvim_create_autocmd("User", {
    pattern = "MiniDiffUpdated",
    desc = "Move to the first review hunk of a file opened from the panel",
    callback = function(event)
      if event.buf ~= buf then
        return
      end
      pcall(vim.api.nvim_del_autocmd, id)
      jump()
    end,
  })
  vim.defer_fn(function()
    pcall(vim.api.nvim_del_autocmd, id)
  end, 2000)
end

---Show a file as it exists in the base revision. Used for deleted files, which
---have no working-tree buffer to diff.
local function open_base_version(session, entry, win)
  Git.file_at_rev(session.root, session.commit, entry.old_path or entry.path, function(result)
    if result.code ~= 0 or not vim.api.nvim_win_is_valid(win) then
      notify(("%s is not readable in %s"):format(entry.path, session.ref), vim.log.levels.WARN)
      return
    end

    local buf = vim.api.nvim_create_buf(true, true)
    local name = ("diffbuf://base/%s@%s"):format(entry.path, session.commit:sub(1, 7))
    pcall(vim.api.nvim_buf_set_name, buf, name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result.stdout or "", "\n"))
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("readonly", true, { buf = buf })
    local filetype = vim.filetype.match({ filename = entry.path, buf = buf })
    if filetype ~= nil then
      vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
    end
    vim.api.nvim_win_set_buf(win, buf)
  end)
end

---@param opts? { focus?: boolean }
function M.open_current(opts)
  opts = opts or {}
  local row = M.row_at()
  if row == nil then
    return
  end

  if row.kind == "dir" then
    M.toggle_node()
    return
  end

  local session = Review.get()
  if session == nil then
    notify("review mode is not active", vim.log.levels.WARN)
    return
  end

  local win = target_window()
  if win == nil then
    return
  end

  local entry = row.entry
  if entry.status == "D" then
    open_base_version(session, entry, win)
  else
    local path = vim.fs.joinpath(session.root, entry.path)
    vim.api.nvim_win_call(win, function()
      vim.cmd.edit(vim.fn.fnameescape(path))
    end)
    jump_to_first_hunk(win, vim.api.nvim_win_get_buf(win))
  end

  if opts.focus ~= false then
    vim.api.nvim_set_current_win(win)
  end
end

function M.toggle_node()
  local row = M.row_at()
  if row == nil or row.kind ~= "dir" then
    return
  end
  state.collapsed[row.path] = not state.collapsed[row.path] or nil
  local line = vim.api.nvim_win_get_cursor(state.win)[1]
  render()
  pcall(
    vim.api.nvim_win_set_cursor,
    state.win,
    { math.min(line, vim.api.nvim_buf_line_count(state.buf)), 0 }
  )
end

function M.close_node()
  local row = M.row_at()
  if row == nil then
    return
  end

  if row.kind == "dir" and not row.collapsed then
    M.toggle_node()
    return
  end

  local parent = vim.fs.dirname(row.path)
  if parent == "." or parent == "" or parent == row.path then
    return
  end
  for index = #state.rows, 1, -1 do
    local candidate = state.rows[index]
    if
      candidate.kind == "dir"
      and (parent == candidate.path or vim.startswith(parent, candidate.path .. "/"))
    then
      vim.api.nvim_win_set_cursor(state.win, { index + header_height, 0 })
      return
    end
  end
end

function M.collapse_all()
  local session = Review.get()
  state.collapsed = {}
  if session ~= nil and session.files ~= nil then
    for _, path in
      ipairs(Tree.dir_paths(session.files, {
        group_dirs = Config.get().panel.group_dirs,
      }))
    do
      state.collapsed[path] = true
    end
  end
  render()
end

function M.expand_all()
  state.collapsed = {}
  render()
end

---@param value? "tree"|"flat"
function M.set_layout(value)
  if value ~= nil then
    state.layout = value
  else
    state.layout = layout() == "tree" and "flat" or "tree"
  end
  render()
  return state.layout
end

function M.refresh()
  Review.load_files()
  render()
end

-- Following the current file -------------------------------------------------

local function follow(path)
  if not is_valid() or path == nil then
    return
  end
  if layout() == "tree" then
    local changed = false
    for collapsed in pairs(state.collapsed) do
      if vim.startswith(path, collapsed .. "/") then
        state.collapsed[collapsed] = nil
        changed = true
      end
    end
    if changed then
      render()
    end
  end

  local line = line_of(path)
  if line ~= nil then
    pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
  end
end

-- Window lifecycle -----------------------------------------------------------

local function install_mappings(buf)
  local function map(lhs, callback, description)
    vim.keymap.set("n", lhs, callback, {
      buffer = buf,
      silent = true,
      desc = description,
    })
  end

  for _, lhs in ipairs({ "<CR>", "o", "l" }) do
    map(lhs, function()
      M.open_current()
    end, "Open the changed file")
  end
  map("<Tab>", function()
    M.open_current({ focus = false })
  end, "Open the changed file and stay in the panel")
  map("h", function()
    M.close_node()
  end, "Collapse the directory or move to the parent")
  map("H", function()
    M.collapse_all()
  end, "Collapse every directory")
  map("L", function()
    M.expand_all()
  end, "Expand every directory")
  map("t", function()
    M.set_layout()
  end, "Toggle the tree and flat layout")
  map("r", function()
    M.refresh()
  end, "Reload the changed-file list")
  map("R", function()
    Review.refresh()
  end, "Re-resolve the base and reload every review surface")
  map("d", function()
    -- The composite buffer replaces the current window, which must not be the
    -- panel itself.
    local win = target_window()
    if win == nil then
      return
    end
    vim.api.nvim_set_current_win(win)
    require("diffbuf").open()
  end, "Open the composite diff buffer")
  map("O", function()
    require("diffbuf.inline").toggle_overlay()
  end, "Toggle the inline diff overview")
  map("q", function()
    M.close()
  end, "Close the panel")
  map("?", function()
    vim.cmd("help diffbuf-panel")
  end, "Show diffbuf.nvim help")
end

local function ensure_autocmds()
  if group ~= nil then
    return
  end
  group = vim.api.nvim_create_augroup("DiffBufPanel", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "DiffBufReviewFilesChanged", "DiffBufReviewRefreshed", "DiffBufReviewStarted" },
    desc = "Re-render the diffbuf.nvim panel",
    callback = function()
      render()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DiffBufReviewStopped",
    desc = "Close the diffbuf.nvim panel with review mode",
    callback = function()
      M.close()
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    desc = "Follow the entered file in the diffbuf.nvim panel",
    callback = function(event)
      if not Config.get().panel.follow or not is_valid() then
        return
      end
      if event.buf == state.buf then
        return
      end
      follow(Review.relative(vim.api.nvim_buf_get_name(event.buf)))
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    desc = "Release diffbuf.nvim panel state",
    callback = function(event)
      if tonumber(event.match) == state.win then
        state.win = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "Restore diffbuf.nvim panel highlight links",
    callback = define_highlights,
  })
end

local function clear_autocmds()
  if group == nil then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, group)
  group = nil
end

local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("undolevels", -1, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "diffbuf-panel", { buf = buf })
  pcall(vim.api.nvim_buf_set_name, buf, "diffbuf://changes")
  install_mappings(buf)
  return buf
end

local function panel_width()
  local width = Config.get().panel.width
  if width <= 1 then
    width = vim.o.columns * width
  end
  return math.max(20, math.floor(width))
end

local function create_window(buf)
  local win = vim.api.nvim_open_win(buf, false, {
    split = Config.get().panel.position,
    win = -1,
    width = panel_width(),
  })

  local options = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    wrap = false,
    list = false,
    spell = false,
    cursorline = true,
    cursorcolumn = false,
    winfixwidth = true,
    winfixbuf = true,
  }
  for name, value in pairs(options) do
    pcall(vim.api.nvim_set_option_value, name, value, { win = win, scope = "local" })
  end

  return win
end

---@param opts? { focus?: boolean }
function M.open(opts)
  opts = opts or {}
  define_highlights()
  ensure_autocmds()

  if is_valid() then
    render()
    if opts.focus then
      vim.api.nvim_set_current_win(state.win)
    end
    return state.win
  end

  if state.buf == nil or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = create_buffer()
  end
  state.win = create_window(state.buf)
  render()

  local session = Review.get()
  if session ~= nil and session.files == nil then
    Review.load_files()
  end

  if opts.focus then
    vim.api.nvim_set_current_win(state.win)
  end
  return state.win
end

function M.close()
  local win, buf = state.win, state.buf
  state.win = nil
  state.buf = nil
  state.rows = {}
  clear_autocmds()

  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf ~= nil and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

---@param opts? { focus?: boolean }
function M.toggle(opts)
  if is_valid() then
    M.close()
    return nil
  end
  return M.open(vim.tbl_extend("force", { focus = true }, opts or {}))
end

M.namespace = namespace
return M
