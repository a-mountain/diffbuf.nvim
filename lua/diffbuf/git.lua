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
---@field commit string Concrete commit every review feature compares against.
---@field diverged boolean Whether `commit` is behind the tip of `ref`.

---Resolve a review base into one commit shared by every review feature.
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

  return { ref = ref, commit = commit, diverged = commit ~= tip }
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

---@param text string `git diff -z --name-status` output
---@return table[]
function M.parse_name_status(text)
  local fields = nul_fields(text)
  local entries = {}
  local index = 1

  while index <= #fields do
    local status = fields[index]
    if status == nil or status == "" then
      break
    end

    if status:match("^[RC]") then
      local old_path, path = fields[index + 1], fields[index + 2]
      index = index + 3
      if path ~= nil and path ~= "" then
        entries[#entries + 1] = {
          status = status:sub(1, 1),
          path = path,
          old_path = old_path ~= "" and old_path or nil,
        }
      end
    else
      local path = fields[index + 1]
      index = index + 2
      if path ~= nil and path ~= "" then
        entries[#entries + 1] = { status = status:sub(1, 1), path = path }
      end
    end
  end

  return entries
end

---@param text string `git diff -z --numstat` output
---@return table<string, table>
function M.parse_numstat(text)
  local fields = nul_fields(text)
  local stats = {}
  local index = 1

  while index <= #fields do
    local field = fields[index]
    if field == nil or field == "" then
      break
    end

    local added, removed, path = field:match("^(%S+)\t(%S+)\t(.*)$")
    if added == nil then
      index = index + 1
    else
      if path == "" then
        -- Renames and copies emit both paths as separate NUL-delimited fields.
        path = fields[index + 2]
        index = index + 3
      else
        index = index + 1
      end
      if path ~= nil and path ~= "" then
        stats[path] = {
          added = tonumber(added) or 0,
          removed = tonumber(removed) or 0,
          binary = added == "-" or removed == "-",
        }
      end
    end
  end

  return stats
end

local function collect(root, jobs, callback)
  local results = {}
  local remaining = #jobs
  local handles = {}

  for index, argv in ipairs(jobs) do
    handles[index] = vim.system(argv, { cwd = root, text = true }, function(result)
      results[index] = result
      remaining = remaining - 1
      if remaining == 0 then
        vim.schedule(function()
          callback(results)
        end)
      end
    end)
  end

  return {
    kill = function(_, signal)
      for _, handle in ipairs(handles) do
        pcall(handle.kill, handle, signal or "sigterm")
      end
    end,
  }
end

---@class diffbuf.ChangedFile
---@field status string One of A, C, D, M, R, T, U or ? for untracked.
---@field path string Path relative to the repository root.
---@field old_path? string Pre-rename path, when the file moved.
---@field added integer
---@field removed integer
---@field binary boolean

---List every file that differs between `rev` and the working tree.
---@param root string
---@param rev string
---@param opts { untracked: boolean }
---@param callback fun(entries: diffbuf.ChangedFile[]?, error: string?)
function M.changed_files(root, rev, opts, callback)
  local jobs = {
    {
      "git",
      "-c",
      "core.quotepath=false",
      "diff",
      "-z",
      "--name-status",
      "--find-renames",
      rev,
      "--",
    },
    {
      "git",
      "-c",
      "core.quotepath=false",
      "diff",
      "-z",
      "--numstat",
      "--find-renames",
      rev,
      "--",
    },
  }
  if opts.untracked then
    jobs[3] = {
      "git",
      "-c",
      "core.quotepath=false",
      "ls-files",
      "--others",
      "--exclude-standard",
      "-z",
    }
  end

  return collect(root, jobs, function(results)
    local status_result = results[1]
    if status_result == nil or status_result.code ~= 0 then
      callback(nil, stderr_message(status_result or {}, "git diff --name-status failed"))
      return
    end

    local entries = M.parse_name_status(status_result.stdout)
    local stats = {}
    if results[2] ~= nil and results[2].code == 0 then
      stats = M.parse_numstat(results[2].stdout)
    end

    for _, entry in ipairs(entries) do
      local stat = stats[entry.path]
      entry.added = stat ~= nil and stat.added or 0
      entry.removed = stat ~= nil and stat.removed or 0
      entry.binary = stat ~= nil and stat.binary or false
    end

    if results[3] ~= nil and results[3].code == 0 then
      for _, path in ipairs(nul_fields(results[3].stdout)) do
        if path ~= "" then
          entries[#entries + 1] = {
            status = "?",
            path = path,
            added = 0,
            removed = 0,
            binary = false,
          }
        end
      end
    end

    table.sort(entries, function(one, two)
      return one.path < two.path
    end)
    callback(entries)
  end)
end

return M
