local cwd = assert(vim.env.DIFFBUF_LIVE_CWD, "DIFFBUF_LIVE_CWD is required")
local expected_files = tonumber(vim.env.DIFFBUF_LIVE_EXPECTED_FILES or "")

local before = vim
  .system({ "git", "status", "--porcelain=v2" }, {
    cwd = cwd,
    text = true,
  })
  :wait()
assert(before.code == 0, before.stderr)

local buf = assert(require("diffbuf").open({ cwd = cwd }))
assert(
  vim.wait(5000, function()
    return vim.b[buf].diffbuf_status == "ready"
  end, 10),
  "live diff did not become ready"
)

local state = assert(require("diffbuf.state").get(buf))
local files = 0
for _, row in ipairs(state.rows) do
  if row.kind == "file" then
    files = files + 1
  end
end
if expected_files ~= nil then
  assert(files == expected_files, ("expected %d files, got %d"):format(expected_files, files))
end

local after = vim
  .system({ "git", "status", "--porcelain=v2" }, {
    cwd = cwd,
    text = true,
  })
  :wait()
assert(after.code == 0, after.stderr)
assert(after.stdout == before.stdout, "live target status changed while opening the diff")
print(("ok: live (%d rows, %d files)"):format(#state.rows, files))
