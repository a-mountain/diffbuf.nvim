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

---@class diffbuf.Fold
---@field kind "file"|"hunk"
---@field added integer Added lines inside the fold.
---@field removed integer Removed lines inside the fold.
---@field hunks? integer File folds only: hunks the file contains.
---@field header? string Hunk folds only: the `@@` line the parser consumed.

---@param text string
---@return table
function M.parse(text)
  local files = {}
  local file
  local hunk
  local hunk_start = false
  local hunk_header
  local hunk_fold
  local old_line
  local new_line

  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^diff %-%-git ") then
      -- A rename or a mode change carries no ---/+++ pair, so keep the paths the
      -- header states as the fallback for naming the file.
      local header_old, header_new = line:match("^diff %-%-git a/(.+) b/(.+)$")
      file = {
        rows = {},
        old_path = nil,
        new_path = nil,
        header_path = header_new or header_old,
        hunks = 0,
        added = 0,
        removed = 0,
      }
      files[#files + 1] = file
      hunk = nil
      hunk_start = false
      hunk_fold = nil
    elseif file ~= nil and line:match("^%-%-%- ") then
      file.old_path = display_path(line:sub(5):match("^[^\t]+"))
    elseif file ~= nil and line:match("^%+%+%+ ") then
      file.new_path = display_path(line:sub(5):match("^[^\t]+"))
    elseif file ~= nil then
      local parsed_hunk = parse_hunk_header(line)
      if parsed_hunk ~= nil then
        hunk = parsed_hunk
        hunk_header = line
        hunk_fold = nil
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
            hunk_fold = { kind = "hunk", added = 0, removed = 0, header = hunk_header }
            row.fold = hunk_fold
            file.hunks = file.hunks + 1
            hunk_start = false
          end
          if row.kind == "added" then
            file.added = file.added + 1
            hunk_fold.added = hunk_fold.added + 1
          elseif row.kind == "deleted" then
            file.removed = file.removed + 1
            hunk_fold.removed = hunk_fold.removed + 1
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

  return M.assemble(files)
end

---Lay parsed files out as buffer lines and the row table that mirrors them one
---to one. Assembling is separate from parsing so a caller can reorder or mark the
---files first and lay them out again.
---@param files table[]
---@return table
function M.assemble(files)
  local lines = {}
  local rows = {}

  for index, file in ipairs(files) do
    local path = file.new_path or file.old_path or file.header_path or "unknown file"
    file.path = path
    lines[#lines + 1] = path .. " --- " .. index .. "/" .. #files
    rows[#rows + 1] = {
      kind = "file",
      path = path,
      old_path = file.old_path,
      new_path = file.new_path,
      generated = file.generated,
      fold = {
        kind = "file",
        hunks = file.hunks,
        added = file.added,
        removed = file.removed,
      },
    }

    for _, row in ipairs(file.rows) do
      row.path = path
      row.old_path = file.old_path
      row.new_path = file.new_path
      row.generated = file.generated
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
