local plugin_root = vim.fn.fnamemodify(vim.env.NVIM_PLUGIN_ROOT or ".", ":p")
local helpers = dofile(vim.fs.joinpath(plugin_root, "tests", "helpers.lua"))
local fixture = helpers.seed_repo()
local log_path = vim.fs.joinpath(fixture.root, "lsp-request.json")

local group = vim.api.nvim_create_augroup("DiffBufTestLsp", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "java",
  callback = function(event)
    vim.lsp.start({
      name = "diffbuf-test",
      cmd = {
        vim.v.progpath,
        "--clean",
        "--headless",
        "-l",
        vim.fs.joinpath(plugin_root, "tests", "fake_lsp.lua"),
      },
      cmd_env = { DIFFBUF_LSP_LOG = log_path },
      root_dir = fixture.root,
    }, { bufnr = event.buf })
  end,
})

local ok, error_message = xpcall(function()
  vim.cmd.cd(fixture.root)
  vim.o.number = true
  vim.wo.statuscolumn = "SRC "
  vim.cmd("DiffBufOpen")
  helpers.wait_ready()

  local composite = vim.api.nvim_get_current_buf()
  local state = require("diffbuf.state").get(composite)
  local target_row
  local expected_line
  for index, row in ipairs(state.rows) do
    if row.text == "  Target stagedChange;" then
      target_row = index
      expected_line = row.new_line
      break
    end
  end
  assert(target_row ~= nil, "fixture line was not rendered")

  vim.api.nvim_win_set_cursor(0, { target_row, 2 })
  vim.api.nvim_feedkeys("gd", "xt", false)

  local expected_source = vim.uv.fs_realpath(fixture.source)
  local opened = vim.wait(5000, function()
    return vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == expected_source
  end, 10)
  if not opened then
    local source_buf = vim.fn.bufnr(fixture.source)
    local clients = vim.tbl_map(function(client)
      return { name = client.name, attached = client.attached_buffers[source_buf] == true }
    end, vim.lsp.get_clients())
    error(
      ("definition result did not open the source buffer; current=%s source_buf=%s loaded=%s filetype=%s request=%s clients=%s messages=%s"):format(
        vim.api.nvim_buf_get_name(0),
        source_buf,
        tostring(source_buf ~= -1 and vim.api.nvim_buf_is_loaded(source_buf)),
        source_buf ~= -1 and vim.bo[source_buf].filetype or "",
        tostring(vim.uv.fs_stat(log_path) ~= nil),
        vim.inspect(clients),
        vim.fn.execute("messages")
      )
    )
  end
  assert(vim.api.nvim_win_get_cursor(0)[1] == 1)
  assert(vim.wo.statuscolumn == "SRC ")
  assert(vim.wo.number == true)
  assert(vim.api.nvim_buf_is_valid(composite))
  assert(vim.bo[composite].buflisted == true)
  assert(vim.bo[composite].filetype == "diffbuf")

  assert(
    vim.wait(1000, function()
      return vim.uv.fs_stat(log_path) ~= nil
    end, 10),
    "fake LSP did not record a definition request"
  )
  local request = vim.json.decode(table.concat(vim.fn.readfile(log_path), "\n"))
  assert(vim.uv.fs_realpath(vim.uri_to_fname(request.textDocument.uri)) == expected_source)
  assert(request.position.line == expected_line - 1)
  assert(request.position.character == 2)
end, debug.traceback)

helpers.cleanup(fixture)
assert(ok, error_message)
print("ok: lsp_definition")
