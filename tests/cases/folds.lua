local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_hunks_repo()

local State = require("diffbuf.state")
local UI = require("diffbuf.ui")

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local ok, error_message = xpcall(function()
  vim.cmd.cd(fixture.root)
  require("diffbuf").setup({})
  vim.cmd("DiffBufOpen")
  helpers.wait_ready()

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  local files, hunks = {}, {}
  for index, row in ipairs(State.get(buf).rows) do
    if row.kind == "file" then
      files[#files + 1] = { line = index, path = row.path }
    elseif row.hunk == true then
      hunks[#hunks + 1] = index
    end
  end
  assert(#files == 2, vim.inspect(files))
  assert(#hunks == 3, "src/long.txt holds two hunks and src/other.txt one")

  -- The window folds the diff itself, without touching what the user configured
  -- for real files.
  assert(vim.wo[win].foldmethod == "expr", vim.wo[win].foldmethod)
  assert(vim.wo[win].foldenable == true)
  assert(vim.wo[win].foldlevel == 99, "everything starts expanded")

  -- A file is one fold, each of its hunks a fold inside it.
  assert(vim.fn.foldlevel(files[1].line) == 1)
  assert(vim.fn.foldlevel(hunks[1]) == 2)
  assert(vim.fn.foldlevel(hunks[1] + 1) == 2, "a hunk body belongs to its hunk fold")
  assert(vim.fn.foldclosed(files[1].line) == -1, "nothing is collapsed to begin with")
  assert(UI.statuscolumn(hunks[1]):find("▾", 1, true), UI.statuscolumn(hunks[1]))
  assert(UI.statuscolumn(hunks[1] + 1):find("▾", 1, true) == nil, "only fold starts are marked")

  -- Collapse one hunk.
  vim.api.nvim_win_set_cursor(win, { hunks[1], 0 })
  press("zc")
  assert(vim.fn.foldclosed(hunks[1]) == hunks[1], "zc collapses the hunk under the cursor")
  assert(vim.fn.foldclosedend(hunks[1]) == hunks[2] - 1, "the fold stops at the next hunk")
  assert(vim.fn.foldclosed(files[1].line) == -1, "the file header stays visible")
  assert(UI.statuscolumn(hunks[1]):find("▸", 1, true), UI.statuscolumn(hunks[1]))

  local hunk_text = vim.fn.foldtextresult(hunks[1])
  assert(hunk_text:find("@@", 1, true), hunk_text)
  assert(hunk_text:find("⋯", 1, true), hunk_text)
  assert(hunk_text:find("+1", 1, true) and hunk_text:find("-1", 1, true), hunk_text)

  -- A second zc collapses the whole file.
  press("zc")
  assert(vim.fn.foldclosed(files[1].line) == files[1].line, "a second zc collapses the file")
  assert(vim.fn.foldclosedend(files[1].line) == files[2].line - 1)

  local file_text = vim.fn.foldtextresult(files[1].line)
  assert(file_text:find(files[1].path, 1, true), file_text)
  assert(file_text:find("2 hunks", 1, true), file_text)
  assert(file_text:find("(generated)", 1, true) == nil, file_text)

  -- zR and zM still work, because 'foldlevel' belongs to the user.
  press("zR")
  assert(vim.fn.foldclosed(files[1].line) == -1 and vim.fn.foldclosed(hunks[1]) == -1)
  press("zM")
  assert(vim.fn.foldclosed(files[1].line) == files[1].line)
  assert(vim.fn.foldclosed(files[2].line) == files[2].line)
  press("zR")

  -- Refreshing rebuilds the rows, so folds must follow the new content.
  vim.fn.writefile(
    { "other changed twice", "and again" },
    vim.fs.joinpath(fixture.root, "src", "other.txt")
  )
  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  local refreshed = State.get(buf).rows
  assert(#refreshed == vim.api.nvim_buf_line_count(buf), "rows keep lining up with the buffer")
  assert(vim.fn.foldlevel(files[1].line) == 1)

  -- Leaving the buffer hands the window's fold options back.
  vim.cmd.edit(fixture.source)
  assert(vim.wo.foldmethod ~= "expr", vim.wo.foldmethod)
  assert(not vim.wo.foldexpr:find("diffbuf", 1, true), vim.wo.foldexpr)
  assert(not vim.wo.foldtext:find("diffbuf", 1, true), vim.wo.foldtext)
  assert(vim.api.nvim_get_option_value("foldmethod", { scope = "global" }) ~= "expr")
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: folds")
