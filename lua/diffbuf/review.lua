local Config = require("diffbuf.config")
local Git = require("diffbuf.git")

local M = {}

---@class diffbuf.Session
---@field root string Repository root as Git reports it.
---@field real_root string Resolved root used for path containment checks.
---@field ref string Base revision as the user named it.
---@field commit string Commit every review feature compares against.
---@field diverged boolean Whether `commit` is the merge base rather than the ref tip.
---@field generation integer Bumped whenever `commit` changes.
---@field files? diffbuf.ChangedFile[]
---@field files_error? string
---@field by_path table<string, diffbuf.ChangedFile>

---@type diffbuf.Session?
local session
local group
local files_job
local files_token = 0

local function notify(message, level)
  vim.notify("diffbuf.nvim: " .. message, level or vim.log.levels.ERROR)
end

local function emit(pattern)
  vim.api.nvim_exec_autocmds("User", {
    pattern = pattern,
    data = session ~= nil and {
      root = session.root,
      ref = session.ref,
      commit = session.commit,
    } or nil,
  })
end

---@return diffbuf.Session?
function M.get()
  return session
end

function M.is_active()
  return session ~= nil
end

---Short description for statuslines: `origin/main` or `origin/main…a1b2c3d`.
---@return string
function M.status()
  if session == nil then
    return ""
  end
  if not session.diverged then
    return session.ref
  end
  return ("%s…%s"):format(session.ref, session.commit:sub(1, 7))
end

---Path relative to the review root, or `nil` when it is outside the review.
---@param path? string
---@return string?
function M.relative(path)
  if session == nil or path == nil or path == "" then
    return nil
  end
  local target = vim.uv.fs_realpath(path) or path
  local root = session.real_root
  if target == root then
    return nil
  end
  local prefix = root .. "/"
  if target:sub(1, #prefix) ~= prefix then
    return nil
  end
  return target:sub(#prefix + 1)
end

---@param relative string
---@return diffbuf.ChangedFile?
function M.entry(relative)
  if session == nil then
    return nil
  end
  return session.by_path[relative]
end

---Path a file had in the base revision, which differs for renames.
---@param relative string
---@return string
function M.base_path(relative)
  local entry = M.entry(relative)
  if entry ~= nil and entry.old_path ~= nil then
    return entry.old_path
  end
  return relative
end

---@return diffbuf.ChangedFile[]?
function M.files()
  return session ~= nil and session.files or nil
end

local function ensure_autocmds()
  if group ~= nil then
    return
  end
  group = vim.api.nvim_create_augroup("DiffBufReview", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    desc = "Refresh the diffbuf.nvim review file list after a write",
    callback = function(event)
      if session == nil then
        return
      end
      if M.relative(vim.api.nvim_buf_get_name(event.buf)) == nil then
        return
      end
      M.load_files()
    end,
  })
end

local function clear_autocmds()
  if group == nil then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, group)
  group = nil
end

---Reload the changed-file list for the active session.
---@param callback? fun(entries: diffbuf.ChangedFile[]?)
function M.load_files(callback)
  if session == nil then
    return
  end

  if files_job ~= nil then
    pcall(files_job.kill, files_job, "sigterm")
    files_job = nil
  end

  files_token = files_token + 1
  local token = files_token
  local generation = session.generation

  files_job = Git.changed_files(session.root, session.commit, {
    untracked = Config.get().review.untracked,
  }, function(entries, error_message)
    if token ~= files_token or session == nil or session.generation ~= generation then
      return
    end
    files_job = nil

    if entries == nil then
      session.files_error = error_message
      notify(error_message)
    else
      session.files = entries
      session.files_error = nil
      session.by_path = {}
      for _, entry in ipairs(entries) do
        session.by_path[entry.path] = entry
      end
    end

    emit("DiffBufReviewFilesChanged")
    if callback ~= nil then
      callback(session.files)
    end
  end)
end

---Locate the repository, falling back to the current file when the working
---directory is outside one.
---@param cwd string
---@param explicit boolean
---@return string? root
---@return string? error
local function repository(cwd, explicit)
  local root, root_error = Git.root(cwd)
  if root ~= nil or explicit then
    return root, root_error
  end

  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or vim.bo.buftype ~= "" then
    return nil, root_error
  end

  local buffer_root = Git.root(vim.fs.dirname(name))
  if buffer_root == nil then
    return nil, root_error
  end
  return buffer_root
end

---@class diffbuf.ReviewOpts
---@field base? string Revision to review against. Defaults to the default branch.
---@field cwd? string Directory used to locate the repository.
---@field inline? boolean Override `review.inline` for this session.
---@field panel? boolean Override `review.panel` for this session.

---Start review mode, or switch the active session to another base.
---@param opts? diffbuf.ReviewOpts
---@return diffbuf.Session?
function M.start(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  vim.validate("opts.base", opts.base, "string", true)
  vim.validate("opts.cwd", opts.cwd, "string", true)
  vim.validate("opts.inline", opts.inline, "boolean", true)
  vim.validate("opts.panel", opts.panel, "boolean", true)

  local config = Config.get().review
  local cwd = opts.cwd or (session ~= nil and session.root) or vim.uv.cwd()
  local root, root_error = repository(cwd, opts.cwd ~= nil)
  if root == nil then
    notify(root_error)
    return nil
  end

  local base, base_error = Git.resolve_base(root, opts.base or config.base, config.merge_base)
  if base == nil then
    notify(base_error)
    return nil
  end

  session = {
    root = root,
    real_root = vim.uv.fs_realpath(root) or root,
    ref = base.ref,
    commit = base.commit,
    diverged = base.diverged,
    generation = (session ~= nil and session.generation or 0) + 1,
    files = nil,
    files_error = nil,
    by_path = {},
  }

  ensure_autocmds()
  emit("DiffBufReviewStarted")

  local inline = opts.inline
  if inline == nil then
    inline = config.inline
  end
  if inline then
    require("diffbuf.inline").enable()
  end

  local panel = opts.panel
  if panel == nil then
    panel = config.panel
  end
  if panel then
    require("diffbuf.panel").open()
  end

  M.load_files()
  return session
end

function M.stop()
  if session == nil then
    return
  end

  if files_job ~= nil then
    pcall(files_job.kill, files_job, "sigterm")
    files_job = nil
  end
  files_token = files_token + 1

  session = nil
  clear_autocmds()
  require("diffbuf.inline").disable()
  require("diffbuf.panel").close()
  emit("DiffBufReviewStopped")
end

---@param opts? diffbuf.ReviewOpts
---@return diffbuf.Session?
function M.toggle(opts)
  if session ~= nil then
    M.stop()
    return nil
  end
  return M.start(opts)
end

---Re-resolve the base commit and reload every review surface.
function M.refresh()
  if session == nil then
    notify("review mode is not active", vim.log.levels.WARN)
    return
  end

  local base, base_error =
    Git.resolve_base(session.root, session.ref, Config.get().review.merge_base)
  if base == nil then
    notify(base_error)
    return
  end

  session.commit = base.commit
  session.diverged = base.diverged
  session.generation = session.generation + 1
  emit("DiffBufReviewRefreshed")

  require("diffbuf.inline").refresh()
  for _, buf in ipairs(require("diffbuf.state").list()) do
    require("diffbuf").refresh(buf)
  end
  M.load_files()
end

return M
