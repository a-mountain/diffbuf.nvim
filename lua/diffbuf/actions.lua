local State = require("diffbuf.state")

local M = {}

local function current_row(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return nil
  end
  return vim.api.nvim_win_get_cursor(win)[1]
end

function M.open_source(buf)
  local state = State.get(buf)
  local row = current_row(buf)
  local item = state and row and state.rows[row]
  if item == nil or item.new_line == nil or item.new_path == nil then
    vim.notify("diffbuf.nvim: this row has no working-tree source location", vim.log.levels.INFO)
    return
  end

  local path = vim.fs.joinpath(state.root, item.new_path)
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { item.new_line, 0 })
end

function M.navigate(buf, kind, direction)
  local state = State.get(buf)
  local row = current_row(buf)
  if state == nil or row == nil then
    return
  end

  local index = row + direction
  while index >= 1 and index <= #state.rows do
    local item = state.rows[index]
    local matches = item.kind == kind or (kind == "hunk" and item.hunk == true)
    if matches then
      vim.api.nvim_win_set_cursor(0, { index, 0 })
      vim.cmd("normal! zz")
      return
    end
    index = index + direction
  end
end

return M
