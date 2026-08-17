local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_repo()

local ok, error_message = xpcall(function()
  assert(vim.fn.exists(":DiffBufOpen") == 2, "runtime command was not registered")
  vim.o.number = true
  vim.o.relativenumber = true
  vim.cmd.cd(fixture.root)
  vim.cmd("DiffBufOpen")
  helpers.wait_ready()

  assert(vim.bo.filetype == "diffbuf")
  assert(vim.bo.buftype == "nofile")
  assert(vim.bo.buflisted == true)
  assert(vim.bo.modifiable == false)
  assert(vim.bo.readonly == true)
  assert(vim.wo.number == false, "composite buffer must not show Neovim line numbers")
  assert(vim.wo.relativenumber == false, "composite buffer must not show relative line numbers")
  assert(vim.api.nvim_get_option_value("number", { scope = "global" }) == true)
  assert(vim.api.nvim_get_option_value("relativenumber", { scope = "global" }) == true)

  vim.wo.number = true
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
  assert(
    vim.wait(100, function()
      return vim.wo.number == false
    end, 10),
    "BufEnter must restore nonumber on the composite buffer"
  )

  local state = require("diffbuf.state").get(vim.api.nvim_get_current_buf())
  assert(state.base == "origin/main")
  assert(#state.rows > 0)

  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(text:find("committedChange", 1, true))
  assert(text:find("stagedChange", 1, true))
  assert(text:find("unstagedChange", 1, true))
  assert(not text:find("@@", 1, true))

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
  local number_count = 0
  for _ in column:gmatch("%d+") do
    number_count = number_count + 1
  end
  assert(number_count == 1, "gutter must show a single working-tree line number")
  assert(column:find("│", 1, true))
  local evaluated = vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
    winid = vim.api.nvim_get_current_win(),
    use_statuscol_lnum = added_row,
  })
  local evaluated_count = 0
  for _ in evaluated.str:gmatch("%d+") do
    evaluated_count = evaluated_count + 1
  end
  assert(evaluated_count == 1)
  assert(evaluated.str:find("│", 1, true))

  local context_row
  for index, row in ipairs(state.rows) do
    if row.old_line ~= nil and row.new_line ~= nil then
      context_row = index
      break
    end
  end
  assert(context_row ~= nil)
  local context_column = require("diffbuf.ui").statuscolumn(context_row)
  local context_numbers = 0
  for _ in context_column:gmatch("%d+") do
    context_numbers = context_numbers + 1
  end
  assert(context_numbers == 1)
  assert(context_column:find(tostring(state.rows[context_row].new_line), 1, true))

  vim.cmd.edit(fixture.source)
  assert(vim.wo.number == true, "source buffers must keep Neovim line numbers")
  assert(vim.wo.relativenumber == true)
  assert(not vim.wo.statuscolumn:find("diffbuf.ui", 1, true))
  vim.wait(50)
  assert(vim.wo.number == true)
  assert(not vim.wo.statuscolumn:find("diffbuf.ui", 1, true))
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: open")
