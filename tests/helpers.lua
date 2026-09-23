local M = {}

local function run(cwd, argv)
  local result = vim.system(argv, { cwd = cwd, text = true }):wait()
  assert(result.code == 0, (result.stderr or result.stdout or table.concat(argv, " ")))
  return result.stdout or ""
end

function M.seed_repo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.joinpath(root, "src"), "p")

  local source = vim.fs.joinpath(root, "src", "Main.java")
  vim.fn.writefile({
    "class Main {",
    "  int value;",
    "}",
    "class Target {}",
  }, source)

  run(root, { "git", "init", "-b", "main" })
  run(root, { "git", "config", "user.name", "diffbuf.nvim tests" })
  run(root, { "git", "config", "user.email", "diffbuf@example.invalid" })
  run(root, { "git", "add", "src/Main.java" })
  run(root, { "git", "commit", "-m", "Initial fixture" })
  run(root, { "git", "remote", "add", "origin", "." })
  run(root, { "git", "update-ref", "refs/remotes/origin/main", "refs/heads/main" })
  run(root, {
    "git",
    "symbolic-ref",
    "refs/remotes/origin/HEAD",
    "refs/remotes/origin/main",
  })

  run(root, { "git", "switch", "-c", "feature" })
  vim.fn.writefile({
    "class Main {",
    "  Target committedChange;",
    "}",
    "class Target {}",
  }, source)
  run(root, { "git", "add", "src/Main.java" })
  run(root, { "git", "commit", "-m", "Add committed branch change" })

  vim.fn.writefile({
    "class Main {",
    "  Target committedChange;",
    "  Target stagedChange;",
    "}",
    "class Target {}",
  }, source)
  run(root, { "git", "add", "src/Main.java" })

  vim.fn.writefile({
    "class Main {",
    "  Target committedChange;",
    "  Target stagedChange;",
    "  Target unstagedChange;",
    "}",
    "class Target {}",
  }, source)

  return {
    root = root,
    source = source,
  }
end

local function write(root, relative, lines)
  local path = vim.fs.joinpath(root, relative)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  return path
end

---Repository exercising every review case: a committed change, a rename, a
---deletion, a new file, staged and unstaged edits, an untracked file, and a
---commit that landed on the base branch after the review branch forked.
function M.seed_review_repo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  run(root, { "git", "init", "-b", "main" })
  run(root, { "git", "config", "user.name", "diffbuf.nvim tests" })
  run(root, { "git", "config", "user.email", "diffbuf@example.invalid" })

  write(root, "src/a.txt", { "one", "two", "three" })
  write(root, "src/deep/nested/b.txt", { "keep" })
  write(root, "lib/renamed.txt", { "old" })
  write(root, "src/gone.txt", { "bye" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Base commit" })
  local fork_point = vim.trim(run(root, { "git", "rev-parse", "HEAD" }))

  run(root, { "git", "switch", "-c", "feature" })
  write(root, "src/a.txt", { "one", "TWO", "three" })
  write(root, "src/deep/nested/b.txt", { "keep", "nested change" })
  write(root, "src/added.txt", { "brand new" })
  run(root, { "git", "mv", "lib/renamed.txt", "lib/newname.txt" })
  run(root, { "git", "rm", "--quiet", "src/gone.txt" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Review branch work" })

  -- A commit that landed on the base branch after the fork. A GitHub-style
  -- review must not show it.
  run(root, { "git", "switch", "main" })
  write(root, "main-only.txt", { "main only" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Base branch moved on" })
  local base_tip = vim.trim(run(root, { "git", "rev-parse", "HEAD" }))
  run(root, { "git", "switch", "feature" })

  run(root, { "git", "remote", "add", "origin", "." })
  run(root, { "git", "update-ref", "refs/remotes/origin/main", "refs/heads/main" })
  run(root, {
    "git",
    "symbolic-ref",
    "refs/remotes/origin/HEAD",
    "refs/remotes/origin/main",
  })

  write(root, "src/a.txt", { "one", "TWO", "three", "four" })
  run(root, { "git", "add", "src/a.txt" })
  write(root, "src/a.txt", { "one", "TWO", "three", "four", "five" })
  write(root, "src/untracked.txt", { "untracked" })

  return {
    root = root,
    fork_point = fork_point,
    base_tip = base_tip,
    source = vim.fs.joinpath(root, "src", "a.txt"),
  }
end

local function seed_origin(root)
  run(root, { "git", "remote", "add", "origin", "." })
  run(root, { "git", "update-ref", "refs/remotes/origin/main", "refs/heads/main" })
  run(root, {
    "git",
    "symbolic-ref",
    "refs/remotes/origin/HEAD",
    "refs/remotes/origin/main",
  })
end

local function seed_empty(root)
  vim.fn.mkdir(root, "p")
  run(root, { "git", "init", "-b", "main" })
  run(root, { "git", "config", "user.name", "diffbuf.nvim tests" })
  run(root, { "git", "config", "user.email", "diffbuf@example.invalid" })
end

---Repository whose .gitattributes marks files generated the way GitHub
---(`linguist-generated`) and GitLab (`gitlab-generated`) do, including the
---explicit negative form that must not count.
function M.seed_generated_repo()
  local root = vim.fn.tempname()
  seed_empty(root)

  write(root, ".gitattributes", {
    "*.lock gitlab-generated=true",
    "gen/**/*.txt linguist-generated",
    "src/kept.txt linguist-generated=false",
  })
  write(root, "src/hand.txt", { "one", "two", "three" })
  write(root, "src/kept.txt", { "kept" })
  write(root, "gen/schema.txt", { "generated one" })
  write(root, "deps.lock", { "lock one" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Base commit" })
  seed_origin(root)

  run(root, { "git", "switch", "-c", "feature" })
  write(root, "src/hand.txt", { "one", "TWO", "three" })
  write(root, "src/kept.txt", { "kept", "still written by hand" })
  write(root, "gen/schema.txt", { "generated one", "generated two", "generated three" })
  write(root, "deps.lock", { "lock two" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Regenerate" })

  return {
    root = root,
    source = vim.fs.joinpath(root, "src", "hand.txt"),
  }
end

---Repository holding a Lua file, whose parser Neovim bundles, next to a file no
---parser claims.
function M.seed_syntax_repo()
  local root = vim.fn.tempname()
  seed_empty(root)

  write(root, "src/mod.lua", {
    "local M = {}",
    "",
    "function M.goodbye(name)",
    '  return "goodbye " .. name',
    "end",
    "",
    "return M",
  })
  write(root, "notes.unknownext", { "plain text one" })
  write(root, "README.md", { "# Title", "", "Call `M.goodbye` to say it." })
  -- A filetype Vim has a syntax script for; whether Tree-sitter can also parse
  -- it depends on the machine, which is the point of having both paths.
  write(root, "run.bat", { "@rem build the thing", "set TARGET=old", "goto end" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Base commit" })
  seed_origin(root)

  run(root, { "git", "switch", "-c", "feature" })
  write(root, "src/mod.lua", {
    "local M = {}",
    "",
    "local function greet(name)",
    '  return "hello " .. name',
    "end",
    "",
    "return M",
  })
  write(root, "notes.unknownext", { "plain text two" })
  write(root, "README.md", { "# Title", "", "Call `M.greet` to say it." })
  write(root, "run.bat", { "@rem build the thing", "set TARGET=new", "goto end" })

  return {
    root = root,
    source = vim.fs.joinpath(root, "src", "mod.lua"),
  }
end

---Repository with one file carrying two distant hunks, so hunk folds have
---something to nest inside.
function M.seed_hunks_repo()
  local root = vim.fn.tempname()
  seed_empty(root)

  local lines = {}
  for index = 1, 40 do
    lines[index] = "line " .. index
  end
  write(root, "src/long.txt", lines)
  write(root, "src/other.txt", { "other" })
  run(root, { "git", "add", "-A" })
  run(root, { "git", "commit", "-m", "Base commit" })
  seed_origin(root)

  run(root, { "git", "switch", "-c", "feature" })
  lines[3] = "line 3 changed"
  lines[30] = "line 30 changed"
  write(root, "src/long.txt", lines)
  write(root, "src/other.txt", { "other changed" })

  return {
    root = root,
    source = vim.fs.joinpath(root, "src", "long.txt"),
  }
end

---@param root string
---@param argv string[]
function M.git(root, argv)
  return run(root, vim.list_extend({ "git" }, argv))
end

function M.minidiff()
  local ok, module = pcall(require, "mini.diff")
  assert(ok, "mini.diff is missing from the runtimepath; run `make deps`")
  module.setup({
    -- Keep the test session free of global mappings.
    mappings = {
      apply = "",
      reset = "",
      textobject = "",
      goto_first = "",
      goto_prev = "",
      goto_next = "",
      goto_last = "",
    },
  })
  return module
end

---@param message string
---@param predicate fun(): boolean
function M.wait_for(message, predicate, timeout)
  assert(vim.wait(timeout or 5000, predicate, 10), message)
end

function M.wait_files(timeout)
  M.wait_for("the review file list did not load", function()
    local session = require("diffbuf.review").get()
    return session ~= nil and session.files ~= nil
  end, timeout)
  return require("diffbuf.review").files()
end

---@param entries diffbuf.ChangedFile[]
---@return table<string, diffbuf.ChangedFile>
function M.by_path(entries)
  local result = {}
  for _, entry in ipairs(entries) do
    result[entry.path] = entry
  end
  return result
end

function M.wait_ready(timeout)
  assert(
    vim.wait(timeout or 3000, function()
      return vim.b.diffbuf_status == "ready"
    end, 10),
    "diffbuf.nvim did not become ready"
  )
end

function M.cleanup(fixture)
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.name == "diffbuf-test" then
      client:stop(true)
    end
  end
  vim.fs.rm(fixture.root, { recursive = true, force = true })
end

return M
