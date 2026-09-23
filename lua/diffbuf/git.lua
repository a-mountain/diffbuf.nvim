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

local function stderr_message(result, fallback)
  local message = trim(result.stderr)
  if message == "" then
    message = trim(result.stdout)
  end
  return message ~= "" and message or fallback
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

  return nil, "could not determine the default branch; pass one explicitly"
end

---@param root string
---@param rev string
---@return string? commit
---@return string? error
function M.rev_parse(root, rev)
  local result = run({ "git", "rev-parse", "--verify", "--quiet", rev .. "^{commit}" }, root)
  local commit = trim(result.stdout)
  if result.code ~= 0 or commit == "" then
    return nil, ("revision '%s' does not exist in this repository"):format(rev)
  end
  return commit
end

---@param root string
---@param one string
---@param two string
---@return string? commit
---@return string? error
function M.merge_base(root, one, two)
  local result = run({ "git", "merge-base", one, two }, root)
  local commit = trim(result.stdout)
  if result.code ~= 0 or commit == "" then
    return nil, ("%s and %s have no merge base"):format(one, two)
  end
  return commit
end

---@class diffbuf.Base
---@field ref string Revision as the user named it.
---@field commit string Concrete commit the buffer compares against.

---Resolve a base revision into one concrete commit.
---@param root string
---@param base? string
---@param use_merge_base boolean
---@return diffbuf.Base?
---@return string? error
function M.resolve_base(root, base, use_merge_base)
  local ref = base
  if ref == nil then
    local ref_error
    ref, ref_error = M.default_branch(root)
    if ref == nil then
      return nil, ref_error
    end
  end

  local tip, tip_error = M.rev_parse(root, ref)
  if tip == nil then
    return nil, tip_error
  end

  local commit = tip
  if use_merge_base then
    local merge_base = M.merge_base(root, tip, "HEAD")
    if merge_base ~= nil then
      commit = merge_base
    end
  end

  return { ref = ref, commit = commit }
end

---Revisions offered as command-line completion candidates.
---@param root string
---@return string[]
function M.refs(root)
  local result = run({
    "git",
    "for-each-ref",
    "--format=%(refname:short)",
    "refs/heads",
    "refs/remotes",
    "refs/tags",
  }, root)
  local refs = { "HEAD" }
  if result.code ~= 0 then
    return refs
  end
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    if line ~= "" and not line:match("/HEAD$") then
      refs[#refs + 1] = line
    end
  end
  return refs
end

function M.diff(root, rev, context, callback)
  return vim.system({
    "git",
    "-c",
    "core.quotepath=false",
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--find-renames",
    "--unified=" .. context,
    rev,
    "--",
  }, {
    cwd = root,
    text = true,
  }, vim.schedule_wrap(callback))
end

---Read one file as it exists in `rev`. A non-zero exit means the path is absent
---from that revision, which is how new and untracked files are recognized.
function M.file_at_rev(root, rev, path, callback)
  return vim.system({
    "git",
    "-c",
    "core.quotepath=false",
    "show",
    ("%s:%s"):format(rev, path),
  }, {
    cwd = root,
    text = true,
  }, vim.schedule_wrap(callback))
end

local function nul_fields(text)
  return vim.split(text or "", "\0", { plain = true })
end

---@param text string `git check-attr -z` output: path, attribute, value triples
---@return table<string, boolean> paths carrying at least one of the attributes
function M.parse_check_attr(text)
  local fields = nul_fields(text)
  local marked = {}

  for index = 1, #fields - 2, 3 do
    local path, value = fields[index], fields[index + 2]
    -- `set` is a bare attribute, `true` an explicit `=true`; `unspecified`,
    -- `unset` and `false` all mean the file is not marked.
    if path ~= "" and (value == "set" or value == "true") then
      marked[path] = true
    end
  end

  return marked
end

---Ask Git which paths are generated. GitHub writes `linguist-generated` in
---.gitattributes, GitLab writes `gitlab-generated`; both collapse those files
---in code review, and so does diffbuf.nvim.
---@param root string
---@param paths string[] Paths relative to `root`.
---@param attributes string[]
---@param callback fun(generated: table<string, boolean>)
function M.generated(root, paths, attributes, callback)
  if #paths == 0 or #attributes == 0 then
    vim.schedule(function()
      callback({})
    end)
    return { kill = function() end }
  end

  local argv = vim.list_extend({ "git", "check-attr", "-z", "--stdin" }, attributes)
  return vim.system(
    argv,
    {
      cwd = root,
      text = true,
      stdin = table.concat(paths, "\0") .. "\0",
    },
    vim.schedule_wrap(function(result)
      -- A failure here only costs the collapsing, so report nothing generated
      -- rather than failing the surface that asked.
      callback(result.code == 0 and M.parse_check_attr(result.stdout) or {})
    end)
  )
end

return M
