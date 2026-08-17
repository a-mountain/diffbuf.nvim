local Tree = require("diffbuf.tree")

local entries = {
  { status = "M", path = "lua/diffbuf/init.lua", added = 4, removed = 1 },
  { status = "A", path = "lua/diffbuf/panel.lua", added = 30, removed = 0 },
  { status = "M", path = "doc/diffbuf.txt", added = 2, removed = 2 },
  { status = "?", path = "deep/single/child/only.lua", added = 0, removed = 0 },
  { status = "M", path = "README.md", added = 1, removed = 1 },
}

local function describe(rows)
  return vim.tbl_map(function(row)
    return ("%s %d %s"):format(row.kind, row.depth, row.label)
  end, rows)
end

local tree = Tree.rows(entries, { layout = "tree" })
assert(
  vim.deep_equal(describe(tree), {
    "dir 0 deep/single/child",
    "file 1 only.lua",
    "dir 0 doc",
    "file 1 diffbuf.txt",
    "dir 0 lua/diffbuf",
    "file 1 init.lua",
    "file 1 panel.lua",
    "file 0 README.md",
  }),
  vim.inspect(describe(tree))
)

local grouped = tree[5]
assert(grouped.path == "lua/diffbuf")
assert(grouped.count == 2)
assert(grouped.added == 34 and grouped.removed == 1)
assert(grouped.collapsed == false)
assert(tree[6].path == "lua/diffbuf/init.lua")
assert(tree[6].entry.status == "M")

local ungrouped = Tree.rows(entries, { layout = "tree", group_dirs = false })
assert(
  vim.deep_equal(describe(ungrouped), {
    "dir 0 deep",
    "dir 1 single",
    "dir 2 child",
    "file 3 only.lua",
    "dir 0 doc",
    "file 1 diffbuf.txt",
    "dir 0 lua",
    "dir 1 diffbuf",
    "file 2 init.lua",
    "file 2 panel.lua",
    "file 0 README.md",
  }),
  vim.inspect(describe(ungrouped))
)

local collapsed = Tree.rows(entries, {
  layout = "tree",
  collapsed = { ["lua/diffbuf"] = true, doc = true },
})
assert(
  vim.deep_equal(describe(collapsed), {
    "dir 0 deep/single/child",
    "file 1 only.lua",
    "dir 0 doc",
    "dir 0 lua/diffbuf",
    "file 0 README.md",
  }),
  vim.inspect(describe(collapsed))
)
assert(collapsed[3].collapsed == true)
assert(collapsed[3].count == 1, "a collapsed directory keeps reporting its file count")

local flat = Tree.rows(entries, { layout = "flat" })
assert(
  vim.deep_equal(describe(flat), {
    "file 0 README.md",
    "file 0 deep/single/child/only.lua",
    "file 0 doc/diffbuf.txt",
    "file 0 lua/diffbuf/init.lua",
    "file 0 lua/diffbuf/panel.lua",
  }),
  vim.inspect(describe(flat))
)
for _, row in ipairs(flat) do
  assert(row.path == row.label, "flat rows show the full path")
  assert(row.entry ~= nil)
end

assert(vim.deep_equal(Tree.dir_paths(entries), {
  "deep/single/child",
  "doc",
  "lua/diffbuf",
}))
assert(vim.deep_equal(Tree.rows({}, { layout = "tree" }), {}))
assert(vim.deep_equal(Tree.rows({}, { layout = "flat" }), {}))

local root_only = Tree.rows({ { status = "A", path = "only.txt", added = 1, removed = 0 } }, {
  layout = "tree",
})
assert(#root_only == 1 and root_only[1].depth == 0 and root_only[1].label == "only.txt")

print("ok: tree")
