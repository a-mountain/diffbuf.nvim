-- Guarded real-repository lane: runs the composite buffer against a real Git
-- worktree and proves it stays untouched.
--   DIFFBUF_LIVE_CWD=/path/to/repo make test-live
local cwd = assert(vim.env.DIFFBUF_LIVE_CWD, "DIFFBUF_LIVE_CWD is required")

local function git(argv)
  local result = vim.system(vim.list_extend({ "git" }, argv), { cwd = cwd, text = true }):wait()
  assert(result.code == 0, table.concat(argv, " ") .. ": " .. (result.stderr or ""))
  return result.stdout or ""
end

local function status()
  return git({ "status", "--porcelain=v2" })
end

local before = status()

local base = vim.env.DIFFBUF_LIVE_BASE
local composite = assert(require("diffbuf").open({ cwd = cwd, base = base }))
assert(
  vim.wait(10000, function()
    return vim.b[composite].diffbuf_status == "ready"
  end, 20),
  "the composite buffer did not become ready"
)
local state = assert(require("diffbuf.state").get(composite))

-- Cross-check the buffer's base against Git itself.
local merge_base = vim.trim(git({ "merge-base", state.base, "HEAD" }))
assert(state.rev == merge_base, ("expected %s, got %s"):format(merge_base, state.rev))

local files, generated, hunks = 0, 0, 0
local win = assert(vim.fn.bufwinid(composite))
for line, row in ipairs(state.rows) do
  if row.kind == "file" then
    files = files + 1
    if row.generated then
      generated = generated + 1
      assert(vim.api.nvim_win_call(win, function()
        return vim.fn.foldclosed(line)
      end) == line, "a generated file loaded expanded: " .. row.path)
    end
  elseif row.hunk then
    hunks = hunks + 1
  end
end

local after = status()
assert(after == before, "the live repository changed while reviewing it")
print(
  ("ok: live (%d files, %d generated collapsed, %d hunks, %d rows)"):format(
    files,
    generated,
    hunks,
    #state.rows
  )
)
