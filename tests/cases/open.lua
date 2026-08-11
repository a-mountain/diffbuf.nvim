local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_repo()

local ok, error_message = xpcall(function()
  assert(vim.fn.exists(":DiffBufOpen") == 2, "runtime command was not registered")
  vim.cmd.cd(fixture.root)
  vim.cmd("DiffBufOpen")
  helpers.wait_ready()

  assert(vim.bo.filetype == "diffbuf")
  assert(vim.bo.buftype == "nofile")
  assert(vim.bo.modifiable == false)
  assert(vim.bo.readonly == true)

  local state = require("diffbuf.state").get(vim.api.nvim_get_current_buf())
  assert(state.base == "origin/main")
  assert(#state.rows > 0)

  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(text:find("committedChange", 1, true))
  assert(text:find("stagedChange", 1, true))
  assert(text:find("unstagedChange", 1, true))

  local gd = vim.fn.maparg("gd", "n", false, true)
  assert(gd.buffer == 1 and gd.desc:find("definition", 1, true))

  local added_row
  for index, row in ipairs(state.rows) do
    if row.kind == "added" then
      added_row = index
      break
    end
  end
  assert(added_row ~= nil)
  local column = require("diffbuf.ui").statuscolumn(added_row)
  assert(column:find("│", 1, true))
  local evaluated = vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
    winid = vim.api.nvim_get_current_win(),
    use_statuscol_lnum = added_row,
  })
  assert(evaluated.str:find("│", 1, true))
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: open")
