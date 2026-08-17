local parsed = require("diffbuf.parser").parse([[
diff --git a/src/A.java b/src/A.java
index 1111111..2222222 100644
--- a/src/A.java
+++ b/src/A.java
@@ -1,2 +1,3 @@
 class A {
+  Target value;
 }
]])

assert(#parsed.files == 1)
assert(#parsed.rows == 4)
assert(parsed.rows[1].kind == "file")
assert(parsed.rows[2].kind == "context" and parsed.rows[2].hunk == true)
assert(parsed.rows[2].old_line == 1 and parsed.rows[2].new_line == 1)
assert(parsed.rows[3].kind == "added" and parsed.rows[3].new_line == 2)
assert(parsed.rows[3].path == "src/A.java")
for _, row in ipairs(parsed.rows) do
  assert(row.kind ~= "hunk")
  assert(not (row.text or ""):find("@@", 1, true))
end
print("ok: parser")
