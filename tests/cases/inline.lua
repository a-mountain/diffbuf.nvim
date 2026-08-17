local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_review_repo()

local Inline = require("diffbuf.inline")
local Review = require("diffbuf.review")
local minidiff = helpers.minidiff()

local function wait_ref(buf, expected)
  helpers.wait_for(
    ("reference text for buffer %d never became %s"):format(buf, vim.inspect(expected)),
    function()
      local data = minidiff.get_buf_data(buf)
      return data ~= nil and data.ref_text == expected
    end
  )
end

local function wait_hunks(buf)
  helpers.wait_for(("buffer %d never produced hunks"):format(buf), function()
    local data = minidiff.get_buf_data(buf)
    return data ~= nil and #data.hunks > 0
  end)
  return minidiff.get_buf_data(buf).hunks
end

local function virtual_lines(buf)
  local count = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    if mark[4] ~= nil and mark[4].virt_lines ~= nil then
      count = count + #mark[4].virt_lines
    end
  end
  return count
end

local ok, error_message = xpcall(function()
  vim.cmd.cd(fixture.root)
  require("diffbuf").setup({ review = { panel = false } })

  -- The host keeps mini.diff off until review mode starts.
  vim.g.minidiff_disable = true
  local user_source = minidiff.config.source

  vim.cmd.edit(fixture.source)
  local source_buf = vim.api.nvim_get_current_buf()
  assert(
    minidiff.get_buf_data(source_buf) == nil,
    "mini.diff must stay disabled before review mode"
  )

  assert(Review.start() ~= nil)
  assert(Inline.is_enabled())
  assert(vim.g.minidiff_disable == false)
  helpers.wait_files()

  wait_ref(source_buf, "one\ntwo\nthree\n")
  local data = minidiff.get_buf_data(source_buf)
  assert(data.summary.source_name == "diffbuf-review", vim.inspect(data.summary))
  local hunks = wait_hunks(source_buf)
  local kinds = vim.tbl_map(function(hunk)
    return ("%s:%d"):format(hunk.type, hunk.buf_start)
  end, hunks)
  assert(vim.deep_equal(kinds, { "change:2", "add:4" }), vim.inspect(kinds))

  -- Overview: off until asked for, then deleted and changed reference lines
  -- show up as virtual lines.
  assert(data.overlay == false, "review mode starts with the overview off")
  assert(virtual_lines(source_buf) == 0)

  assert(Inline.toggle_overlay() == true)
  assert(minidiff.get_buf_data(source_buf).overlay == true)
  helpers.wait_for("the overlay never rendered reference text", function()
    return virtual_lines(source_buf) > 0
  end)

  assert(Inline.toggle_overlay() == false)
  helpers.wait_for("the overlay was not cleared", function()
    return virtual_lines(source_buf) == 0
  end)

  -- The overview can also start with the session.
  require("diffbuf").setup({ review = { panel = false, overlay = true } })
  assert(Review.start() ~= nil)
  helpers.wait_files()
  helpers.wait_for("review.overlay did not turn the overview on", function()
    local restarted = minidiff.get_buf_data(source_buf)
    return restarted ~= nil and restarted.overlay == true and virtual_lines(source_buf) > 0
  end)
  require("diffbuf").setup({ review = { panel = false } })

  -- A renamed file compares against its pre-rename path in the base.
  vim.cmd.edit(vim.fs.joinpath(fixture.root, "lib", "newname.txt"))
  local renamed_buf = vim.api.nvim_get_current_buf()
  wait_ref(renamed_buf, "old\n")

  -- An untracked file is entirely new, so the whole buffer is one add hunk.
  vim.cmd.edit(vim.fs.joinpath(fixture.root, "src", "untracked.txt"))
  local untracked_buf = vim.api.nvim_get_current_buf()
  wait_ref(untracked_buf, "")
  local untracked_hunks = wait_hunks(untracked_buf)
  assert(#untracked_hunks == 1 and untracked_hunks[1].type == "add", vim.inspect(untracked_hunks))

  -- Files outside the review are declined so other sources can handle them.
  local outside = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "outside" }, outside)
  vim.cmd.edit(outside)
  local outside_buf = vim.api.nvim_get_current_buf()
  assert(Inline.attach(outside_buf) == false, "buffers outside the review must be declined")
  local outside_data = minidiff.get_buf_data(outside_buf)
  assert(
    outside_data == nil or outside_data.summary.source_name ~= "diffbuf-review",
    vim.inspect(outside_data and outside_data.summary)
  )

  -- Switching the base reloads reference text everywhere.
  assert(Review.start({ base = "HEAD" }) ~= nil)
  helpers.wait_files()
  wait_ref(source_buf, "one\nTWO\nthree\n")

  -- Excluding untracked files makes the source decline them instead.
  require("diffbuf").setup({ review = { panel = false, untracked = false } })
  assert(Review.start({ base = "HEAD" }) ~= nil)
  helpers.wait_files()
  helpers.wait_for("an untracked buffer stayed attached", function()
    local untracked_data = minidiff.get_buf_data(untracked_buf)
    return untracked_data == nil or untracked_data.summary.source_name ~= "diffbuf-review"
  end)

  Review.stop()
  assert(not Inline.is_enabled())
  assert(not Inline.overlay_enabled())
  assert(vim.g.minidiff_disable == true, "stopping review mode restores the host setting")
  assert(minidiff.config.source == user_source, "stopping review mode restores the user's source")
  assert(minidiff.get_buf_data(source_buf) == nil, "review buffers are released")
  assert(virtual_lines(source_buf) == 0, "the overlay is cleared with review mode")

  -- Starting again re-attaches the same buffers.
  require("diffbuf").setup({ review = { panel = false } })
  assert(Review.start() ~= nil)
  helpers.wait_files()
  wait_ref(source_buf, "one\ntwo\nthree\n")
  Review.stop()

  vim.fs.rm(outside, { force = true })
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: inline")
