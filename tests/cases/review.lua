local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_review_repo()

local Review = require("diffbuf.review")

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end

local events = {}
local group = vim.api.nvim_create_augroup("DiffBufReviewTest", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = {
    "DiffBufReviewStarted",
    "DiffBufReviewStopped",
    "DiffBufReviewRefreshed",
    "DiffBufReviewFilesChanged",
  },
  callback = function(event)
    events[#events + 1] = { pattern = event.match, data = event.data }
  end,
})

local ok, error_message = xpcall(function()
  assert(vim.fn.exists(":DiffBufReview") == 2, "review commands were not registered")
  vim.cmd.cd(fixture.root)

  -- Default: GitHub-style comparison against the merge base of the default
  -- branch, so commits that landed on the base after the fork stay out.
  require("diffbuf").setup({ review = { panel = false, inline = false } })
  vim.cmd("DiffBufReview")
  local session = assert(Review.get(), "review mode did not start")
  assert(session.ref == "origin/main", session.ref)
  assert(session.commit == fixture.fork_point, session.commit)
  assert(
    session.diverged == true,
    "the base branch moved on, so the base tip is not the merge base"
  )
  assert(session.root == vim.uv.fs_realpath(fixture.root) or session.root == fixture.root)
  assert(Review.is_active())
  assert(Review.status() == "origin/main…" .. fixture.fork_point:sub(1, 7), Review.status())
  assert(events[1].pattern == "DiffBufReviewStarted")
  assert(events[1].data.commit == fixture.fork_point)

  local files = helpers.wait_files()
  local by_path = helpers.by_path(files)
  local paths = vim.tbl_keys(by_path)
  table.sort(paths)
  assert(
    vim.deep_equal(paths, {
      "lib/newname.txt",
      "src/a.txt",
      "src/added.txt",
      "src/deep/nested/b.txt",
      "src/gone.txt",
      "src/untracked.txt",
    }),
    vim.inspect(paths)
  )
  assert(
    by_path["main-only.txt"] == nil,
    "a commit on the base branch must not appear in the review"
  )

  assert(by_path["src/a.txt"].status == "M")
  assert(by_path["src/a.txt"].added == 3 and by_path["src/a.txt"].removed == 1)
  assert(by_path["src/added.txt"].status == "A" and by_path["src/added.txt"].added == 1)
  assert(by_path["src/gone.txt"].status == "D" and by_path["src/gone.txt"].removed == 1)
  assert(by_path["src/deep/nested/b.txt"].status == "M")
  assert(by_path["lib/newname.txt"].status == "R")
  assert(by_path["lib/newname.txt"].old_path == "lib/renamed.txt")
  assert(by_path["src/untracked.txt"].status == "?")
  assert(vim.tbl_contains(
    vim.tbl_map(function(event)
      return event.pattern
    end, events),
    "DiffBufReviewFilesChanged"
  ))

  assert(
    Review.base_path("lib/newname.txt") == "lib/renamed.txt",
    "renames resolve to the base path"
  )
  assert(Review.base_path("src/a.txt") == "src/a.txt")
  assert(Review.relative(fixture.source) == "src/a.txt", Review.relative(fixture.source) or "nil")
  assert(Review.relative("/etc/hosts") == nil)
  assert(Review.relative("") == nil)

  -- A write inside the review reloads the file list.
  vim.cmd.edit(fixture.source)
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "six" })
  vim.cmd("silent write")
  helpers.wait_for("BufWritePost did not reload the file list", function()
    local entry = Review.entry("src/a.txt")
    return entry ~= nil and entry.added == 4
  end)

  -- An explicit base narrows the review to working-tree changes.
  assert(Review.start({ base = "HEAD" }) ~= nil)
  assert(Review.get().ref == "HEAD")
  local head_files = helpers.wait_files()
  local head_paths = vim.tbl_keys(helpers.by_path(head_files))
  table.sort(head_paths)
  assert(vim.deep_equal(head_paths, { "src/a.txt", "src/untracked.txt" }), vim.inspect(head_paths))

  -- An unknown revision reports an error and leaves the session alone.
  local before = notifications[#notifications]
  assert(Review.start({ base = "definitely/not/a/ref" }) == nil)
  assert(notifications[#notifications] ~= before, "an unknown revision must be reported")
  assert(notifications[#notifications].message:find("does not exist", 1, true))
  assert(notifications[#notifications].level == vim.log.levels.ERROR)
  assert(Review.get().ref == "HEAD", "a failed switch keeps the previous session")

  -- Two-dot comparison keeps the base branch commits in scope.
  require("diffbuf").setup({ review = { merge_base = false, panel = false, inline = false } })
  assert(Review.start({ base = "origin/main" }) ~= nil)
  assert(Review.get().commit == fixture.base_tip, "without merge_base the ref tip is used")
  assert(Review.get().diverged == false)
  assert(Review.status() == "origin/main")
  local two_dot = helpers.by_path(helpers.wait_files())
  assert(two_dot["main-only.txt"] ~= nil, "two-dot comparison includes base branch commits")
  assert(two_dot["main-only.txt"].status == "D")

  -- Untracked files can be excluded.
  require("diffbuf").setup({
    review = { untracked = false, panel = false, inline = false },
  })
  assert(Review.start({ base = "HEAD" }) ~= nil)
  local tracked_only = helpers.by_path(helpers.wait_files())
  assert(tracked_only["src/untracked.txt"] == nil)
  assert(tracked_only["src/a.txt"] ~= nil)

  Review.stop()
  assert(Review.get() == nil)
  assert(not Review.is_active())
  assert(Review.status() == "")
  assert(Review.relative(fixture.source) == nil)
  assert(Review.files() == nil)
  assert(
    not pcall(vim.api.nvim_get_autocmds, { group = "DiffBufReview" }),
    "stopping review mode must remove its augroup"
  )
  assert(events[#events].pattern == "DiffBufReviewStopped")

  Review.stop()
  assert(Review.toggle({ base = "HEAD" }) ~= nil, "toggle starts a session")
  assert(Review.toggle() == nil, "toggle stops the session")

  -- Outside a repository nothing starts.
  local outside = vim.fn.tempname()
  vim.fn.mkdir(outside, "p")
  assert(Review.start({ cwd = outside }) == nil)
  assert(notifications[#notifications].message:find("diffbuf.nvim", 1, true))

  -- With the working directory outside a repository, the current file locates it.
  vim.cmd.cd(outside)
  vim.cmd.edit(fixture.source)
  local from_buffer = assert(Review.start(), "the current file did not locate the repository")
  assert(from_buffer.root == fixture.root or from_buffer.root == vim.uv.fs_realpath(fixture.root))
  Review.stop()

  vim.cmd.enew()
  assert(Review.start() == nil, "an unnamed buffer outside a repository starts nothing")

  vim.cmd.cd(fixture.root)
  vim.fs.rm(outside, { recursive = true, force = true })
end, debug.traceback)

vim.notify = original_notify
helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: review")
