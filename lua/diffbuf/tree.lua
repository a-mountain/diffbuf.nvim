local M = {}

---@class diffbuf.Row
---@field kind "dir"|"file"
---@field path string Directory or file path relative to the repository root.
---@field label string Text shown for the row.
---@field depth integer Indentation level, starting at 0.
---@field collapsed? boolean Directory rows only.
---@field count? integer Directory rows only: changed files below it.
---@field added integer
---@field removed integer
---@field entry? diffbuf.ChangedFile File rows only.

local function child_dir(parent, name)
  local existing = parent.dirs[name]
  if existing ~= nil then
    return existing
  end
  local node = {
    name = name,
    path = parent.path == "" and name or (parent.path .. "/" .. name),
    dirs = {},
    dir_order = {},
    files = {},
  }
  parent.dirs[name] = node
  parent.dir_order[#parent.dir_order + 1] = node
  return node
end

local function build(entries)
  local root = { name = "", path = "", dirs = {}, dir_order = {}, files = {} }
  for _, entry in ipairs(entries) do
    local parts = vim.split(entry.path, "/", { plain = true })
    local node = root
    for index = 1, #parts - 1 do
      node = child_dir(node, parts[index])
    end
    node.files[#node.files + 1] = { name = parts[#parts], entry = entry }
  end
  return root
end

local function totals(node)
  local added, removed, count = 0, 0, 0
  for _, file in ipairs(node.files) do
    added = added + (file.entry.added or 0)
    removed = removed + (file.entry.removed or 0)
    count = count + 1
  end
  for _, dir in ipairs(node.dir_order) do
    local child = totals(dir)
    added = added + child.added
    removed = removed + child.removed
    count = count + child.count
  end
  node.totals = { added = added, removed = removed, count = count }
  return node.totals
end

---Follow a chain of directories that each hold exactly one changed
---subdirectory, so `lua/diffbuf/inline.lua` needs one row instead of three.
local function join_chain(node)
  local label = node.name
  local current = node
  while #current.dir_order == 1 and #current.files == 0 do
    current = current.dir_order[1]
    label = label .. "/" .. current.name
  end
  return current, label
end

local function by_name(one, two)
  local a, b = one.name:lower(), two.name:lower()
  if a == b then
    return one.name < two.name
  end
  return a < b
end

local function flatten(node, depth, opts, rows)
  local dirs = vim.list_slice(node.dir_order, 1, #node.dir_order)
  table.sort(dirs, by_name)
  local files = vim.list_slice(node.files, 1, #node.files)
  table.sort(files, by_name)

  for _, dir in ipairs(dirs) do
    local target, label = dir, dir.name
    if opts.group_dirs then
      target, label = join_chain(dir)
    end
    local collapsed = opts.collapsed[target.path] == true
    rows[#rows + 1] = {
      kind = "dir",
      path = target.path,
      label = label,
      depth = depth,
      collapsed = collapsed,
      count = target.totals.count,
      added = target.totals.added,
      removed = target.totals.removed,
    }
    if not collapsed then
      flatten(target, depth + 1, opts, rows)
    end
  end

  for _, file in ipairs(files) do
    rows[#rows + 1] = {
      kind = "file",
      path = file.entry.path,
      label = file.name,
      depth = depth,
      added = file.entry.added or 0,
      removed = file.entry.removed or 0,
      entry = file.entry,
    }
  end
end

---@class diffbuf.RowOpts
---@field layout? "tree"|"flat"
---@field collapsed? table<string, boolean>
---@field group_dirs? boolean

---@param entries diffbuf.ChangedFile[]
---@param opts? diffbuf.RowOpts
---@return diffbuf.Row[]
function M.rows(entries, opts)
  opts = opts or {}
  local rows = {}

  if opts.layout == "flat" then
    local sorted = vim.list_slice(entries, 1, #entries)
    table.sort(sorted, function(one, two)
      return one.path < two.path
    end)
    for _, entry in ipairs(sorted) do
      rows[#rows + 1] = {
        kind = "file",
        path = entry.path,
        label = entry.path,
        depth = 0,
        added = entry.added or 0,
        removed = entry.removed or 0,
        entry = entry,
      }
    end
    return rows
  end

  local root = build(entries)
  totals(root)
  flatten(root, 0, {
    collapsed = opts.collapsed or {},
    group_dirs = opts.group_dirs ~= false,
  }, rows)
  return rows
end

---Every directory path a fully expanded tree would show.
---@param entries diffbuf.ChangedFile[]
---@param opts? diffbuf.RowOpts
---@return string[]
function M.dir_paths(entries, opts)
  opts = vim.tbl_extend("force", opts or {}, { layout = "tree", collapsed = {} })
  local paths = {}
  for _, row in ipairs(M.rows(entries, opts)) do
    if row.kind == "dir" then
      paths[#paths + 1] = row.path
    end
  end
  return paths
end

return M
