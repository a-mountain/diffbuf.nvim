local parsed = require("diffbuf.parser").parse([[
diff --git a/src/A.java b/src/A.java
index 1111111..2222222 100644
--- a/src/A.java
+++ b/src/A.java
@@ -1,2 +1,3 @@
 class A {
+  Target value;
 }
@@ -20,3 +21,3 @@ class A {
   int keep;
-  int old;
+  int new;
diff --git a/src/B.java b/src/B.java
--- a/src/B.java
+++ b/src/B.java
@@ -1 +1 @@
-old
+new
]])

assert(#parsed.files == 2)
assert(#parsed.rows == 10)
assert(#parsed.lines == #parsed.rows, "every row owns exactly one buffer line")
assert(parsed.rows[1].kind == "file")
assert(parsed.rows[2].kind == "context" and parsed.rows[2].hunk == true)
assert(parsed.rows[2].old_line == 1 and parsed.rows[2].new_line == 1)
assert(parsed.rows[3].kind == "added" and parsed.rows[3].new_line == 2)
assert(parsed.rows[3].path == "src/A.java")
assert(parsed.rows[5].hunk == true, "the second hunk starts a new fold")
assert(parsed.rows[8].kind == "file" and parsed.rows[8].path == "src/B.java")
for _, row in ipairs(parsed.rows) do
  assert(row.kind ~= "hunk")
  assert(not (row.text or ""):find("@@", 1, true))
end

-- Fold metadata: one fold per file, one per hunk, and nothing on the lines in
-- between.
assert(
  vim.deep_equal(parsed.rows[1].fold, {
    kind = "file",
    hunks = 2,
    added = 2,
    removed = 1,
  }),
  vim.inspect(parsed.rows[1].fold)
)
assert(
  vim.deep_equal(parsed.rows[2].fold, {
    kind = "hunk",
    added = 1,
    removed = 0,
    header = "@@ -1,2 +1,3 @@",
  }),
  vim.inspect(parsed.rows[2].fold)
)
assert(
  vim.deep_equal(parsed.rows[5].fold, {
    kind = "hunk",
    added = 1,
    removed = 1,
    header = "@@ -20,3 +21,3 @@ class A {",
  }),
  vim.inspect(parsed.rows[5].fold)
)
assert(
  vim.deep_equal(parsed.rows[8].fold, {
    kind = "file",
    hunks = 1,
    added = 1,
    removed = 1,
  }),
  vim.inspect(parsed.rows[8].fold)
)
assert(
  vim.deep_equal(parsed.rows[9].fold, {
    kind = "hunk",
    added = 1,
    removed = 1,
    header = "@@ -1 +1 @@",
  }),
  vim.inspect(parsed.rows[9].fold)
)
for _, index in ipairs({ 3, 4, 6, 7, 10 }) do
  assert(parsed.rows[index].fold == nil, "only file and hunk starts own a fold")
end

-- A pure rename carries no ---/+++ pair, so the header has to name the file.
local renamed = require("diffbuf.parser").parse([[
diff --git a/lib/old.txt b/lib/new.txt
similarity index 100%
rename from lib/old.txt
rename to lib/new.txt
]])
assert(#renamed.rows == 1)
assert(renamed.rows[1].path == "lib/new.txt", renamed.rows[1].path)
assert(renamed.lines[1] == "lib/new.txt --- 1/1", renamed.lines[1])
assert(renamed.rows[1].new_path == nil, "a rename with no body has no line to jump to")

local binary = require("diffbuf.parser").parse([[
diff --git a/logo.png b/logo.png
index 1111111..2222222 100644
Binary files a/logo.png and b/logo.png differ
]])
assert(#binary.rows == 2)
assert(binary.rows[1].kind == "file")
assert(
  vim.deep_equal(binary.rows[1].fold, {
    kind = "file",
    hunks = 0,
    added = 0,
    removed = 0,
  }),
  vim.inspect(binary.rows[1].fold)
)
assert(binary.rows[2].kind == "meta" and binary.rows[2].fold == nil)

-- Laying the files out is separate from parsing them, so a caller can reorder
-- them and renumber the headers.
local reordered = require("diffbuf.parser").assemble({ parsed.files[2], parsed.files[1] })
assert(reordered.lines[1] == "src/B.java --- 1/2", reordered.lines[1])
assert(reordered.lines[4] == "src/A.java --- 2/2", reordered.lines[4])
assert(#reordered.rows == 10 and #reordered.lines == 10)
assert(reordered.rows[1].path == "src/B.java" and reordered.rows[4].path == "src/A.java")

parsed.files[1].generated = true
local marked = require("diffbuf.parser").assemble(parsed.files)
assert(marked.rows[1].generated == true, "the file row carries the flag")
assert(marked.rows[3].generated == true, "and so does every row below it")
assert(marked.rows[8].generated == nil, "src/B.java is untouched")

print("ok: parser")
