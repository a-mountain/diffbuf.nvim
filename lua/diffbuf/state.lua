local M = {}

local states = {}

function M.create(buf, values)
  local state = vim.tbl_extend("force", {
    buf = buf,
    generation = 0,
    job = nil,
    rows = {},
    status = "loading",
  }, values or {})
  states[buf] = state

  vim.api.nvim_buf_attach(buf, false, {
    on_detach = function()
      local current = states[buf]
      if current ~= nil then
        current.generation = current.generation + 1
        if current.job ~= nil then
          pcall(current.job.kill, current.job, "sigterm")
        end
        states[buf] = nil
      end
    end,
  })

  return state
end

function M.get(buf)
  return states[buf]
end

---Every live composite buffer, so a base change can refresh all of them.
---@return integer[]
function M.list()
  local buffers = {}
  for buf in pairs(states) do
    if vim.api.nvim_buf_is_valid(buf) then
      buffers[#buffers + 1] = buf
    end
  end
  table.sort(buffers)
  return buffers
end

return M
