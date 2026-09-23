local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_syntax_repo()

local Syntax = require("diffbuf.syntax")
local State = require("diffbuf.state")

---@return table<integer, string[]> highlight groups per 1-based buffer line
local function captures(buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, Syntax.namespace, 0, -1, { details = true })
  local groups = {}
  for _, mark in ipairs(marks) do
    local line = mark[2] + 1
    groups[line] = groups[line] or {}
    table.insert(groups[line], mark[4].hl_group)
  end
  return groups
end

local function line_of(rows, path, needle)
  local inside = false
  for index, row in ipairs(rows) do
    if row.kind == "file" then
      inside = row.path == path
    elseif inside and (row.text or ""):find(needle, 1, true) then
      return index
    end
  end
  return nil
end

local ok, error_message = xpcall(function()
  assert(pcall(vim.treesitter.language.add, "lua"), "the bundled Lua parser is missing")

  vim.cmd.cd(fixture.root)
  require("diffbuf").setup({})
  vim.cmd("DiffBufOpen")
  helpers.wait_ready()

  local buf = vim.api.nvim_get_current_buf()
  local rows = State.get(buf).rows
  local groups = captures(buf)
  assert(next(groups) ~= nil, "the composite buffer got no Tree-sitter highlights")

  -- An added line of Lua is highlighted as Lua, not as one flat run.
  local added = assert(line_of(rows, "src/mod.lua", "local function greet"))
  assert(rows[added].kind == "added", rows[added].kind)
  local on_added = assert(groups[added], "an added Lua line has no captures")
  assert(vim.tbl_contains(on_added, "@keyword.lua"), vim.inspect(on_added))
  assert(vim.tbl_contains(on_added, "@function.lua"), vim.inspect(on_added))

  -- Removed lines keep their language too, and context lines are covered.
  local removed = assert(line_of(rows, "src/mod.lua", "goodbye"))
  assert(rows[removed].kind == "deleted", rows[removed].kind)
  assert(groups[removed] ~= nil, "a removed line lost its highlighting")

  -- The captures sit above the DiffAdd line highlight, so the background of the
  -- row survives underneath them.
  local marks = vim.api.nvim_buf_get_extmarks(buf, Syntax.namespace, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    assert(mark[4].priority > 110, vim.inspect(mark[4]))
  end
  local ui_marks = vim.api.nvim_buf_get_extmarks(
    buf,
    require("diffbuf.ui").namespace,
    { added - 1, 0 },
    { added - 1, -1 },
    { details = true }
  )
  assert(#ui_marks == 1 and ui_marks[1][4].line_hl_group == "DiffAdd", vim.inspect(ui_marks))

  -- Injected languages carry most of Markdown's colour, so they have to be
  -- walked as well as the root tree.
  local markdown = assert(line_of(rows, "README.md", "M.greet"))
  local injected = false
  for _, group in ipairs(assert(groups[markdown], "a Markdown line has no captures")) do
    injected = injected or group:find("markdown_inline", 1, true) ~= nil
  end
  assert(injected, vim.inspect(groups[markdown]))

  -- A filetype with no Tree-sitter parser falls back to Vim's syntax engine, so
  -- a batch file is coloured whatever the machine has installed.
  local batch = assert(line_of(rows, "run.bat", "set TARGET=new"))
  local on_batch = assert(groups[batch], "a .bat line got no highlighting")
  local dosbatch_lang = vim.treesitter.language.get_lang("dosbatch")
  if not (dosbatch_lang ~= nil and pcall(vim.treesitter.language.add, dosbatch_lang)) then
    for _, hl in ipairs(on_batch) do
      assert(hl:sub(1, 1) ~= "@", "without a parser the groups come from Vim: " .. hl)
      assert(vim.fn.hlexists(hl) == 1, hl .. " is not a real highlight group")
    end
  end

  -- File headers are not source, and a file without a parser is left alone.
  local header
  for index, row in ipairs(rows) do
    if row.kind == "file" and row.path == "src/mod.lua" then
      header = index
      break
    end
  end
  assert(groups[assert(header)] == nil, "the file header must not be parsed as source")
  local plain = assert(line_of(rows, "notes.unknownext", "plain text"))
  assert(groups[plain] == nil, "a file with no filetype stays plain")

  -- Naming that extension is enough to colour it, and the rule reaches Neovim's
  -- own detection too.
  require("diffbuf").setup({ filetypes = { extension = { unknownext = "lua" } } })
  assert(vim.filetype.match({ filename = "x.unknownext" }) == "lua")
  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  local named = captures(buf)
  local plain_again = assert(line_of(State.get(buf).rows, "notes.unknownext", "plain text"))
  assert(named[plain_again] ~= nil, "the configured filetype was not applied")

  -- Refreshing rebuilds the highlights against the new rows.
  vim.fn.writefile({ "local x = 1", "local y = 2" }, vim.fs.joinpath(fixture.root, "src/mod.lua"))
  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  local refreshed = captures(buf)
  assert(next(refreshed) ~= nil, "refreshing dropped the highlighting")
  for line in pairs(refreshed) do
    assert(line <= vim.api.nvim_buf_line_count(buf), "a stale highlight outlived the refresh")
  end

  -- The feature can be turned off.
  require("diffbuf").setup({ syntax = false })
  vim.cmd("DiffBufRefresh")
  helpers.wait_ready()
  assert(next(captures(buf)) == nil, "syntax = false must leave the buffer plain")
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: syntax")
