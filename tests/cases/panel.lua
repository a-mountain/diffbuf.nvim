local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_review_repo()

local Panel = require("diffbuf.panel")
local Review = require("diffbuf.review")

local function panel_buf()
  local win = assert(Panel.win(), "the panel window is gone")
  return vim.api.nvim_win_get_buf(win)
end

local function lines()
  return vim.api.nvim_buf_get_lines(panel_buf(), 0, -1, false)
end

local function line_with(needle)
  for index, line in ipairs(lines()) do
    if line:find(needle, 1, true) then
      return index
    end
  end
  return nil
end

local function focus_panel(lnum)
  local win = assert(Panel.win())
  vim.api.nvim_set_current_win(win)
  if lnum ~= nil then
    vim.api.nvim_win_set_cursor(win, { lnum, 0 })
  end
  return win
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local ok, error_message = xpcall(function()
  vim.cmd.cd(fixture.root)
  local editor_win = vim.api.nvim_get_current_win()
  require("diffbuf").setup({ review = { inline = false }, panel = { width = 30 } })

  vim.cmd("DiffBufReview")
  assert(Panel.is_open(), "review mode did not open the panel")
  local panel_win = assert(Panel.win())
  assert(panel_win ~= editor_win)
  assert(
    vim.api.nvim_get_current_win() == editor_win,
    "opening the panel with review mode must not steal focus"
  )
  assert(vim.api.nvim_win_get_width(panel_win) == 30)
  assert(vim.bo[panel_buf()].filetype == "diffbuf-panel")
  assert(vim.bo[panel_buf()].buftype == "nofile")
  assert(vim.bo[panel_buf()].modifiable == false)
  assert(vim.wo[panel_win].number == false)
  assert(vim.wo[panel_win].winfixwidth == true)
  assert(vim.wo[panel_win].winfixbuf == true)
  assert(vim.wo[panel_win].cursorline == true)

  helpers.wait_files()
  helpers.wait_for("the panel never rendered the changed files", function()
    return line_with("a.txt") ~= nil
  end)

  assert(lines()[1]:find("origin/main", 1, true), lines()[1])
  assert(lines()[2]:find("6 files", 1, true), lines()[2])
  assert(lines()[2]:find("[tree]", 1, true), lines()[2])

  -- Tree layout groups the single-child chain into one row.
  assert(line_with("deep/nested") ~= nil, table.concat(lines(), "\n"))
  local a_line = assert(line_with("a.txt"))
  local row = assert(Panel.row_at(a_line))
  assert(row.kind == "file" and row.path == "src/a.txt", vim.inspect(row))
  assert(Panel.row_at(1) == nil, "header lines are not rows")

  -- Flat layout shows full paths.
  focus_panel(a_line)
  press("t")
  assert(lines()[2]:find("[flat]", 1, true), lines()[2])
  assert(line_with("src/deep/nested/b.txt") ~= nil, table.concat(lines(), "\n"))
  press("t")
  assert(lines()[2]:find("[tree]", 1, true))

  -- Collapse and expand every directory.
  focus_panel(4)
  press("H")
  for _, row_line in ipairs(lines()) do
    assert(not row_line:find("a.txt", 1, true), "collapsing must hide files")
  end
  press("L")
  assert(line_with("a.txt") ~= nil)

  -- Collapse one directory with `h`, then reopen it with `l`.
  local src_line = assert(line_with("▾ src"))
  focus_panel(src_line)
  press("h")
  assert(line_with("▸ src") ~= nil, table.concat(lines(), "\n"))
  press("l")
  assert(line_with("▾ src") ~= nil)

  -- Opening a file uses the editor window, not the panel.
  focus_panel(assert(line_with("a.txt")))
  press("<CR>")
  assert(vim.api.nvim_get_current_win() == editor_win, "the file must open in the editor window")
  assert(
    vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(fixture.source),
    vim.api.nvim_buf_get_name(0)
  )
  assert(Panel.is_open(), "opening a file keeps the panel")
  assert(vim.api.nvim_win_get_buf(panel_win) == panel_buf(), "the panel keeps its own buffer")

  -- The panel follows the entered file.
  vim.cmd.edit(vim.fs.joinpath(fixture.root, "src", "added.txt"))
  helpers.wait_for("the panel did not follow the entered file", function()
    local cursor = vim.api.nvim_win_get_cursor(panel_win)[1]
    local followed = Panel.row_at(cursor)
    return followed ~= nil and followed.path == "src/added.txt"
  end)

  -- `<Tab>` opens without leaving the panel.
  focus_panel(assert(line_with("a.txt")))
  press("<Tab>")
  assert(vim.api.nvim_get_current_win() == panel_win, "<Tab> keeps focus in the panel")
  assert(
    vim.uv.fs_realpath(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win)))
      == vim.uv.fs_realpath(fixture.source)
  )

  -- A deleted file opens its base revision, because it has no working-tree copy.
  focus_panel(assert(line_with("gone.txt")))
  press("<CR>")
  helpers.wait_for("the deleted file did not open its base revision", function()
    return vim.api
      .nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win))
      :find("diffbuf://base/src/gone.txt", 1, true) ~= nil
  end)
  local base_buf = vim.api.nvim_win_get_buf(editor_win)
  assert(vim.api.nvim_buf_get_lines(base_buf, 0, 1, false)[1] == "bye")
  assert(vim.bo[base_buf].modifiable == false)

  -- Closing the panel releases its window and buffer.
  local buf_before_close = panel_buf()
  focus_panel()
  press("q")
  assert(not Panel.is_open())
  assert(not vim.api.nvim_win_is_valid(panel_win))
  assert(not vim.api.nvim_buf_is_valid(buf_before_close))
  assert(Review.is_active(), "closing the panel does not stop review mode")

  -- Toggling reopens it, focused this time.
  local reopened = assert(require("diffbuf").panel_toggle())
  assert(vim.api.nvim_get_current_win() == reopened)
  helpers.wait_for("the reopened panel is empty", function()
    return line_with("a.txt") ~= nil
  end)

  -- Stopping review mode closes the panel.
  Review.stop()
  assert(not Panel.is_open())
  assert(
    not pcall(vim.api.nvim_get_autocmds, { group = "DiffBufPanel" }),
    "closing the panel must remove its augroup"
  )

  -- The panel can start review mode by itself.
  vim.api.nvim_set_current_win(editor_win)
  assert(require("diffbuf").panel_toggle() ~= nil)
  assert(Review.is_active(), "the panel starts review mode when needed")
  assert(Panel.is_open())
  require("diffbuf").panel_toggle()
  assert(not Panel.is_open())
  Review.stop()
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: panel")
