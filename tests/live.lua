-- Guarded real-repository lane: runs every review surface against a real Git
-- worktree and proves it stays untouched.
--   DIFFBUF_LIVE_CWD=/path/to/repo make test-live
local cwd = assert(vim.env.DIFFBUF_LIVE_CWD, "DIFFBUF_LIVE_CWD is required")
local expected_files = tonumber(vim.env.DIFFBUF_LIVE_EXPECTED_FILES or "")

local function git(argv)
  local result = vim.system(vim.list_extend({ "git" }, argv), { cwd = cwd, text = true }):wait()
  assert(result.code == 0, table.concat(argv, " ") .. ": " .. (result.stderr or ""))
  return result.stdout or ""
end

local function status()
  return git({ "status", "--porcelain=v2" })
end

local function set_of(text)
  local paths = {}
  for line in text:gmatch("[^\n]+") do
    if line ~= "" then
      paths[line] = true
    end
  end
  return paths
end

local before = status()

-- The host owns mini.diff setup; do the same here without global mappings.
require("mini.diff").setup({
  mappings = {
    apply = "",
    reset = "",
    textobject = "",
    goto_first = "",
    goto_prev = "",
    goto_next = "",
    goto_last = "",
  },
})

local Review = require("diffbuf.review")
local session = assert(Review.start({ cwd = cwd }), "review mode did not start")
print(("live: %s against %s (%s)"):format(session.root, session.ref, session.commit:sub(1, 8)))

-- Cross-check the file list against Git itself rather than against the parser.
local merge_base = vim.trim(git({ "merge-base", session.ref, "HEAD" }))
assert(session.commit == merge_base, ("expected %s, got %s"):format(merge_base, session.commit))
local expected = set_of(git({ "diff", "--name-only", "--find-renames", merge_base, "--" }))
for path in pairs(set_of(git({ "ls-files", "--others", "--exclude-standard" }))) do
  expected[path] = true
end

assert(
  vim.wait(10000, function()
    return Review.files() ~= nil
  end, 20),
  "the review file list did not load"
)
local files = Review.files()

local actual = {}
for _, entry in ipairs(files) do
  actual[entry.path] = true
end
for path in pairs(expected) do
  assert(actual[path], "missing from the review: " .. path)
end
for path in pairs(actual) do
  assert(expected[path], "not reported by git: " .. path)
end
if expected_files ~= nil then
  assert(#files == expected_files, ("expected %d files, got %d"):format(expected_files, #files))
end

-- The panel renders every changed file.
local Panel = require("diffbuf.panel")
assert(Panel.is_open(), "the panel did not open")
local panel_buf = vim.api.nvim_win_get_buf(assert(Panel.win()))
local rendered = table.concat(vim.api.nvim_buf_get_lines(panel_buf, 0, -1, false), "\n")
assert(rendered:find(session.ref, 1, true), "the panel header lacks the base revision")

-- The inline diff reads the base revision of a real file.
local Inline = require("diffbuf.inline")
assert(Inline.is_enabled(), "the inline diff did not turn on")
local sample
for _, entry in ipairs(files) do
  -- Removed lines are what the overview has to prove it can show.
  if entry.status == "M" and not entry.binary and entry.removed > 0 then
    sample = entry
    break
  end
end

if sample ~= nil then
  local minidiff = require("mini.diff")
  vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(session.root, sample.path)))
  local buf = vim.api.nvim_get_current_buf()
  assert(
    vim.wait(10000, function()
      local data = minidiff.get_buf_data(buf)
      return data ~= nil and data.ref_text ~= nil and #data.hunks > 0
    end, 20),
    "the review diff for " .. sample.path .. " never arrived"
  )
  local data = minidiff.get_buf_data(buf)
  assert(data.summary.source_name == "diffbuf-review", vim.inspect(data.summary))
  local from_git = git({ "show", ("%s:%s"):format(merge_base, sample.old_path or sample.path) })
  assert(data.ref_text == from_git, "reference text does not match git show for " .. sample.path)
  assert(#data.hunks > 0, "a modified file produced no hunks: " .. sample.path)

  local function virtual_lines()
    local count = 0
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if mark[4] ~= nil and mark[4].virt_lines ~= nil then
        count = count + #mark[4].virt_lines
      end
    end
    return count
  end

  assert(data.overlay == false, "the overview starts off")
  assert(virtual_lines() == 0)
  assert(Inline.toggle_overlay() == true)
  assert(
    vim.wait(5000, function()
      return virtual_lines() > 0
    end, 20),
    "the overview did not show removed lines for " .. sample.path
  )
  local shown = virtual_lines()
  assert(Inline.toggle_overlay() == false)
  assert(
    vim.wait(5000, function()
      return virtual_lines() == 0
    end, 20),
    "the overview did not clear for " .. sample.path
  )
  print(
    ("live: %s has %d hunks, overview showed %d reference lines"):format(
      sample.path,
      #data.hunks,
      shown
    )
  )
end

-- The composite buffer agrees with the session base.
local composite = assert(require("diffbuf").open({ cwd = cwd }))
assert(
  vim.wait(10000, function()
    return vim.b[composite].diffbuf_status == "ready"
  end, 20),
  "the composite buffer did not become ready"
)
local composite_state = assert(require("diffbuf.state").get(composite))
assert(composite_state.rev == session.commit)
local composite_files = 0
for _, row in ipairs(composite_state.rows) do
  if row.kind == "file" then
    composite_files = composite_files + 1
  end
end

Review.stop()
assert(not Inline.is_enabled())
assert(not Panel.is_open())

local after = status()
assert(after == before, "the live repository changed while reviewing it")
print(
  ("ok: live (%d changed files, %d composite files, %d rows)"):format(
    #files,
    composite_files,
    #composite_state.rows
  )
)
