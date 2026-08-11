local M = {}

local function run(argv, cwd)
  return vim
    .system(argv, {
      cwd = cwd,
      text = true,
    })
    :wait()
end

local function trim(text)
  return (text or ""):gsub("%s+$", "")
end

function M.root(cwd)
  local result = run({ "git", "rev-parse", "--show-toplevel" }, cwd)
  if result.code ~= 0 then
    return nil, trim(result.stderr) ~= "" and trim(result.stderr) or "not inside a Git worktree"
  end
  return trim(result.stdout)
end

local function ref_exists(root, ref)
  return run({ "git", "rev-parse", "--verify", "--quiet", ref .. "^{commit}" }, root).code == 0
end

function M.default_branch(root)
  local result = run({
    "git",
    "symbolic-ref",
    "--quiet",
    "--short",
    "refs/remotes/origin/HEAD",
  }, root)
  local branch = trim(result.stdout)
  if result.code == 0 and branch ~= "" then
    return branch
  end

  for _, candidate in ipairs({ "origin/main", "main", "origin/master", "master" }) do
    if ref_exists(root, candidate) then
      return candidate
    end
  end

  return nil, "could not determine the default branch; pass one to :DiffBufOpen"
end

function M.diff(root, base, context, callback)
  return vim.system({
    "git",
    "-c",
    "core.quotepath=false",
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--find-renames",
    "--unified=" .. context,
    base,
    "--",
  }, {
    cwd = root,
    text = true,
  }, vim.schedule_wrap(callback))
end

return M
