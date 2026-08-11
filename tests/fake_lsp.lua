local log_path = assert(vim.env.DIFFBUF_LSP_LOG, "DIFFBUF_LSP_LOG is required")

local function read_message()
  local content_length
  while true do
    local line = io.read("*l")
    if line == nil then
      return nil
    end
    line = line:gsub("\r$", "")
    if line == "" then
      break
    end
    local length = line:match("^[Cc]ontent%-[Ll]ength:%s*(%d+)$")
    if length ~= nil then
      content_length = tonumber(length)
    end
  end
  if content_length == nil then
    return nil
  end
  local body = io.read(content_length)
  return vim.json.decode(body)
end

local function send(message)
  local body = vim.json.encode(message)
  io.write(("Content-Length: %d\r\n\r\n%s"):format(#body, body))
  io.flush()
end

while true do
  local message = read_message()
  if message == nil then
    break
  end

  if message.method == "initialize" then
    send({
      jsonrpc = "2.0",
      id = message.id,
      result = {
        capabilities = {
          definitionProvider = true,
          textDocumentSync = 1,
        },
        serverInfo = { name = "diffbuf-test", version = "1" },
      },
    })
  elseif message.method == "textDocument/definition" then
    local file = assert(io.open(log_path, "w"))
    file:write(vim.json.encode(message.params))
    file:close()
    send({
      jsonrpc = "2.0",
      id = message.id,
      result = {
        uri = message.params.textDocument.uri,
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 0 },
        },
      },
    })
  elseif message.method == "shutdown" then
    send({ jsonrpc = "2.0", id = message.id, result = vim.NIL })
  elseif message.method == "exit" then
    break
  elseif message.id ~= nil then
    send({ jsonrpc = "2.0", id = message.id, result = vim.NIL })
  end
end
