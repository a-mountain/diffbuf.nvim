local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_generated_repo()

local Git = require("diffbuf.git")
local State = require("diffbuf.state")

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
  require("diffbuf").setup({})

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
  require("diffbuf").setup({ generated = { sort_last = false } })
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

  -- An empty attribute list turns the detection off.
  require("diffbuf").setup({ generated = { attributes = {} } })
  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  for _, row in ipairs(State.get(buf).rows) do
    assert(row.generated == nil, "nothing is marked generated once detection is off")
  end
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: generated")
