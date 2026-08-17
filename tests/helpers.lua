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
