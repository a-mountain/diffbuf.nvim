local M = {}

local function display_path(path)
  if path == nil or path == "/dev/null" then
    return nil
  end
  return path:gsub("^[ab]/", "")
end

local function parse_hunk_header(line)
  local old_start, old_count, new_start, new_count =
    line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if old_start == nil then
    return nil
  end
  return {
    old_start = tonumber(old_start),
    old_count = old_count == "" and 1 or tonumber(old_count),
    new_start = tonumber(new_start),
    new_count = new_count == "" and 1 or tonumber(new_count),
  }
end

---@param text string
---@return table
function M.parse(text)
  local files = {}
  local file
  local hunk
  local hunk_start = false
  local old_line
  local new_line

  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^diff %-%-git ") then
      file = { rows = {}, old_path = nil, new_path = nil }
      files[#files + 1] = file
      hunk = nil
      hunk_start = false
    elseif file ~= nil and line:match("^%-%-%- ") then
      file.old_path = display_path(line:sub(5):match("^[^\t]+"))
    elseif file ~= nil and line:match("^%+%+%+ ") then
      file.new_path = display_path(line:sub(5):match("^[^\t]+"))
    elseif file ~= nil then
      local parsed_hunk = parse_hunk_header(line)
      if parsed_hunk ~= nil then
        hunk = parsed_hunk
        old_line = hunk.old_start
        new_line = hunk.new_start
        hunk_start = true
      elseif hunk ~= nil then
        local prefix = line:sub(1, 1)
        local row
        if prefix == " " then
          row = {
            kind = "context",
            text = line:sub(2),
            old_line = old_line,
            new_line = new_line,
          }
          old_line = old_line + 1
          new_line = new_line + 1
        elseif prefix == "+" then
          row = {
            kind = "added",
            text = line:sub(2),
            new_line = new_line,
          }
          new_line = new_line + 1
        elseif prefix == "-" then
          row = {
            kind = "deleted",
            text = line:sub(2),
            old_line = old_line,
          }
          old_line = old_line + 1
        elseif prefix == "\\" then
          row = {
            kind = "meta",
            text = line,
          }
        end
        if row ~= nil then
          if hunk_start then
            row.hunk = true
            hunk_start = false
          end
          file.rows[#file.rows + 1] = row
        end
      elseif line:match("^Binary files ") or line:match("^GIT binary patch") then
        file.rows[#file.rows + 1] = {
          kind = "meta",
          text = line,
        }
      end
    end
  end

  local lines = {}
  local rows = {}
  for index, parsed_file in ipairs(files) do
    local path = parsed_file.new_path or parsed_file.old_path or "unknown file"
    lines[#lines + 1] = path .. " --- " .. index .. "/" .. #files
    rows[#rows + 1] = {
      kind = "file",
      path = path,
      old_path = parsed_file.old_path,
      new_path = parsed_file.new_path,
    }

    for _, row in ipairs(parsed_file.rows) do
      row.path = path
      row.old_path = parsed_file.old_path
      row.new_path = parsed_file.new_path
      lines[#lines + 1] = row.text
      rows[#rows + 1] = row
    end
  end

  return {
    files = files,
    lines = lines,
    rows = rows,
  }
end

return M
