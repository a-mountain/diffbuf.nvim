local Config = require("diffbuf.config")
local State = require("diffbuf.state")

local M = {}
local method = "textDocument/definition"

local function notify(message, level)
  vim.notify("diffbuf.nvim: " .. message, level or vim.log.levels.INFO)
end

local function definition_handler(client, composite_buf)
  return function(error, result)
    if State.get(composite_buf) == nil then
      return
    end
    if error ~= nil then
      notify(error.message or "definition request failed", vim.log.levels.ERROR)
      return
    end
    if result == nil or vim.tbl_isempty(result) then
      notify("definition not found")
      return
    end

    local locations = (result.uri ~= nil or result.targetUri ~= nil) and { result } or result
    if #locations == 1 then
      vim.lsp.util.show_document(locations[1], client.offset_encoding, {
        focus = true,
        reuse_win = true,
      })
      return
    end

    local items = vim.lsp.util.locations_to_items(locations, client.offset_encoding)
    vim.fn.setqflist({}, " ", {
      title = "LSP definitions",
      items = items,
    })
    vim.cmd("copen")
  end
end

local function request_definition(composite_buf, source_buf, line, byte_col, deadline)
  if not vim.api.nvim_buf_is_valid(composite_buf) or not vim.api.nvim_buf_is_valid(source_buf) then
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = source_buf, method = method })
  if #clients == 0 then
    if vim.uv.now() < deadline then
      vim.defer_fn(function()
        request_definition(composite_buf, source_buf, line, byte_col, deadline)
      end, 50)
    else
      notify("no LSP client providing definitions attached to the source file", vim.log.levels.WARN)
    end
    return
  end

  local client = clients[1]
  local source_line = vim.api.nvim_buf_get_lines(source_buf, line - 1, line, false)[1] or ""
  local column = math.min(byte_col, #source_line)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(source_buf) },
    position = {
      line = line - 1,
      character = vim.str_utfindex(source_line, client.offset_encoding, column, false),
    },
  }

  local sent = client:request(method, params, definition_handler(client, composite_buf), source_buf)
  if not sent then
    notify("the LSP client rejected the definition request", vim.log.levels.ERROR)
  end
end

function M.definition(buf)
  local state = State.get(buf)
  local win = vim.fn.bufwinid(buf)
  if state == nil or win == -1 then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local item = state.rows[cursor[1]]
  if item == nil or item.new_line == nil or item.new_path == nil then
    notify("this row has no working-tree LSP location")
    return
  end

  local path = vim.fs.joinpath(state.root, item.new_path)
  local source_buf = vim.fn.bufadd(path)
  vim.fn.bufload(source_buf)

  local displayed_line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1]
  local source_line =
    vim.api.nvim_buf_get_lines(source_buf, item.new_line - 1, item.new_line, false)[1]
  if displayed_line ~= source_line then
    notify("the source file changed; refresh the diff before using LSP", vim.log.levels.WARN)
    return
  end

  local timeout = Config.get().lsp_attach_timeout_ms
  request_definition(buf, source_buf, item.new_line, cursor[2], vim.uv.now() + timeout)
end

return M
