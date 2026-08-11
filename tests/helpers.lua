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
