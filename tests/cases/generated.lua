local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_generated_repo()

local Git = require("diffbuf.git")
local Panel = require("diffbuf.panel")
local Review = require("diffbuf.review")
local State = require("diffbuf.state")

local function panel_lines()
  local win = assert(Panel.win(), "the panel window is gone")
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function line_with(needle)
  for index, line in ipairs(panel_lines()) do
    if line:find(needle, 1, true) then
      return index
    end
  end
  return nil
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local ok, error_message = xpcall(function()
  -- `set` is a bare attribute and `true` an explicit `=true`; everything else,
  -- including an explicit `=false`, leaves the file alone.
  local marked = Git.parse_check_attr(table.concat({
    "deps.lock",
    "gitlab-generated",
    "true",
    "deps.lock",
    "linguist-generated",
    "unspecified",
    "gen/schema.txt",
    "linguist-generated",
    "set",
    "src/kept.txt",
    "linguist-generated",
    "false",
    "src/hand.txt",
    "linguist-generated",
    "unspecified",
  }, "\0") .. "\0")
  assert(
    vim.deep_equal(marked, { ["deps.lock"] = true, ["gen/schema.txt"] = true }),
    vim.inspect(marked)
  )

  vim.cmd.cd(fixture.root)
  local editor_win = vim.api.nvim_get_current_win()
  require("diffbuf").setup({ review = { inline = false }, panel = { width = 40 } })

  vim.cmd("DiffBufReview")
  local by_path = helpers.by_path(helpers.wait_files())
  assert(by_path["deps.lock"].generated == true, "*.lock is gitlab-generated")
  assert(by_path["gen/schema.txt"].generated == true, "gen/**/*.txt is linguist-generated")
  assert(by_path["src/hand.txt"].generated == false)
  assert(by_path["src/kept.txt"].generated == false, "linguist-generated=false is not generated")

  -- The panel leaves generated files out and says how many it dropped.
  helpers.wait_for("the panel never rendered the changed files", function()
    return line_with("hand.txt") ~= nil
  end)
  assert(line_with("deps.lock") == nil, "generated files start hidden")
  assert(line_with("schema.txt") == nil)
  assert(
    line_with("▾ gen") == nil,
    "a directory holding only generated files disappears with them"
  )
  assert(panel_lines()[2]:find("2 files", 1, true), panel_lines()[2])
  assert(panel_lines()[2]:find("2 generated hidden", 1, true), panel_lines()[2])

  local panel_win = assert(Panel.win())
  vim.api.nvim_set_current_win(panel_win)
  vim.api.nvim_win_set_cursor(panel_win, { 4, 0 })
  press("gh")
  assert(line_with("deps.lock") ~= nil, table.concat(panel_lines(), "\n"))
  assert(line_with("schema.txt") ~= nil)
  assert(panel_lines()[2]:find("4 files", 1, true), panel_lines()[2])
  assert(not panel_lines()[2]:find("generated hidden", 1, true), panel_lines()[2])
  press("gh")
  assert(line_with("deps.lock") == nil, "gh hides them again")
  assert(panel_lines()[2]:find("2 generated hidden", 1, true))

  -- The composite buffer loads with the generated files already collapsed.
  vim.api.nvim_set_current_win(editor_win)
  vim.cmd("DiffBufOpen")
  helpers.wait_ready()
  local buf = vim.api.nvim_get_current_buf()
  local rows = State.get(buf).rows
  local file_lines = {}
  for index, row in ipairs(rows) do
    if row.kind == "file" then
      file_lines[row.path] = index
    end
  end
  local lock, hand = assert(file_lines["deps.lock"]), assert(file_lines["src/hand.txt"])
  local schema = assert(file_lines["gen/schema.txt"])

  -- Generated files move behind the hand-written ones, keeping Git's order
  -- within each group, and the headers renumber to match.
  local order = {}
  for _, row in ipairs(rows) do
    if row.kind == "file" then
      order[#order + 1] = row.path
    end
  end
  assert(
    vim.deep_equal(order, { "src/hand.txt", "src/kept.txt", "deps.lock", "gen/schema.txt" }),
    vim.inspect(order)
  )
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "src/hand.txt --- 1/4")
  assert(vim.api.nvim_buf_get_lines(buf, lock - 1, lock, false)[1] == "deps.lock --- 3/4")

  assert(rows[lock].generated == true)
  assert(rows[hand].generated == nil)
  assert(vim.fn.foldclosed(lock) == lock, "a generated file loads collapsed")
  assert(vim.fn.foldclosed(schema) == schema)
  assert(vim.fn.foldclosed(hand) == -1, "hand-written files stay expanded")
  assert(require("diffbuf.ui").statuscolumn(lock):find("▸", 1, true))

  local fold_text = vim.fn.foldtextresult(lock)
  assert(fold_text:find("deps.lock", 1, true), fold_text)
  assert(fold_text:find("(generated)", 1, true), fold_text)

  -- gh expands them, and expands nothing else.
  press("gh")
  assert(vim.fn.foldclosed(lock) == -1, "gh expands the generated files")
  assert(vim.fn.foldclosed(schema) == -1)
  press("gh")
  assert(vim.fn.foldclosed(lock) == lock, "gh collapses them again")

  -- Re-entering the buffer restores the collapsed state.
  press("zR")
  assert(vim.fn.foldclosed(lock) == -1)
  vim.cmd.edit(fixture.source)
  vim.cmd("buffer " .. buf)
  helpers.wait_for("re-entering the buffer did not collapse the generated files", function()
    return vim.fn.foldclosed(lock) == lock
  end)

  -- generated.sort_last = false leaves the diff in Git's order.
  require("diffbuf").setup({ review = { inline = false }, generated = { sort_last = false } })
  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  local git_order = {}
  for _, row in ipairs(State.get(buf).rows) do
    if row.kind == "file" then
      git_order[#git_order + 1] = row.path
    end
  end
  assert(
    vim.deep_equal(git_order, { "deps.lock", "gen/schema.txt", "src/hand.txt", "src/kept.txt" }),
    vim.inspect(git_order)
  )
  assert(State.get(buf).rows[1].generated == true, "they are still marked, just not moved")

  -- An empty attribute list turns the detection off everywhere.
  require("diffbuf").setup({ review = { inline = false }, generated = { attributes = {} } })
  local reloaded = false
  Review.load_files(function()
    reloaded = true
  end)
  helpers.wait_for("the changed-file list did not reload", function()
    return reloaded
  end)
  assert(helpers.by_path(Review.files())["deps.lock"].generated == false)
  helpers.wait_for("the panel kept hiding files that are no longer generated", function()
    return line_with("deps.lock") ~= nil
  end)

  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  for _, row in ipairs(State.get(buf).rows) do
    assert(row.generated == nil, "nothing is marked generated once detection is off")
  end

  Review.stop()
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: generated")
