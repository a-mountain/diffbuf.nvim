local Config = require("diffbuf.config")
local State = require("diffbuf.state")

local M = {}

local namespace = vim.api.nvim_create_namespace("diffbuf.syntax")

-- Captures have to win over the DiffAdd and DiffDelete line highlights, which
-- own the background of the row. Query priorities keep their relative order
-- inside the band above them.
local base_priority = 115
-- A file whose diff is longer than this is left plain: parsing it would block
-- the main loop for a buffer nobody reads top to bottom.
local max_region_lines = 5000
-- Highlight this far beyond the view, so scrolling lands on coloured text.
local margin = 60

-- Vim's own syntax engine is scanned this many lines at a time, so a long file
-- costs only what the window shows.
local legacy_chunk_lines = 120

---@class diffbuf.SyntaxRegion
---@field filetype string
---@field lang? string Tree-sitter language, when a parser is installed.
---@field first integer First buffer line of the file's diff body.
---@field last integer Last buffer line of it.

local buffers = {}
local watchers = {}
local languages = {}

---The filetype of a path and, when a parser is installed for it, its
---Tree-sitter language. Resolution is cached per filetype, not per file,
---because a diff holds many files of the same kind.
---@param path string
---@return string? filetype
---@return string? lang
local function resolve(path)
  local filetype = vim.filetype.match({ filename = path })
  -- Everything downstream builds an Ex command out of the name.
  if filetype == nil or filetype:match("^[%w_.+%-]+$") == nil then
    return nil, nil
  end

  local cached = languages[filetype]
  if cached == nil then
    local lang = vim.treesitter.language.get_lang(filetype)
    -- A parser without a highlights query colours nothing, so treat it as
    -- missing and let Vim's syntax engine have the file.
    local usable = lang ~= nil
      and pcall(vim.treesitter.language.add, lang)
      and vim.treesitter.query.get(lang, "highlights") ~= nil
    cached = usable and lang or false
    languages[filetype] = cached
  end
  return filetype, cached or nil
end

---One region per changed file Neovim can name a filetype for. Rows and buffer
---lines line up, so a region is just the line range between two file headers.
---@param rows table[]
---@return diffbuf.SyntaxRegion[]
local function build_regions(rows)
  local regions = {}
  local current

  for index, row in ipairs(rows) do
    if row.kind == "file" then
      current = nil
      local filetype, lang = resolve(row.path)
      if filetype ~= nil then
        current = { filetype = filetype, lang = lang, first = index + 1, last = index }
        regions[#regions + 1] = current
      end
    elseif current ~= nil and row.kind ~= "meta" then
      current.last = index
    end
  end

  return vim.tbl_filter(function(region)
    return region.last >= region.first and region.last - region.first < max_region_lines
  end, regions)
end

---Injected languages carry most of the colour in some filetypes, Markdown above
---all, so walk the whole language tree rather than only its root.
---@param tree vim.treesitter.LanguageTree
---@param callback fun(tree: TSTree, lang: string)
local function each_tree(tree, callback)
  for _, parsed in pairs(tree:trees()) do
    callback(parsed, tree:lang())
  end
  for _, child in pairs(tree:children()) do
    each_tree(child, callback)
  end
end

---Parse one file's diff body on its own and project the captures back onto the
---composite buffer. The body is the new file with the removed lines still in
---place, so it is not always valid source; Tree-sitter recovers from that and
---colours what it can.
---@param buf integer
---@param region diffbuf.SyntaxRegion
local function highlight_region(buf, region)
  local lines = vim.api.nvim_buf_get_lines(buf, region.first - 1, region.last, false)
  if #lines == 0 then
    return
  end

  local text = table.concat(lines, "\n")
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, region.lang)
  if not ok or parser == nil then
    return
  end
  if not pcall(parser.parse, parser, true) then
    return
  end

  local offset = region.first - 1
  each_tree(parser, function(tree, lang)
    local query = vim.treesitter.query.get(lang, "highlights")
    if query == nil then
      return
    end

    for id, node, metadata in query:iter_captures(tree:root(), text, 0, -1) do
      local name = query.captures[id]
      -- Captures named with a leading underscore exist for the query, not for a
      -- highlight group.
      if name:sub(1, 1) ~= "_" then
        local start_row, start_col, end_row, end_col = node:range()
        pcall(vim.api.nvim_buf_set_extmark, buf, namespace, offset + start_row, start_col, {
          end_row = offset + end_row,
          end_col = end_col,
          hl_group = ("@%s.%s"):format(name, lang),
          priority = base_priority + (tonumber(metadata.priority) or 100) - 100,
          strict = false,
        })
      end
    end
  end)
end

-- Vim syntax fallback --------------------------------------------------------

local benches = {}
local loaded = {}

---A workbench buffer per filetype, holding that filetype's syntax rules. Nil
---when Vim has no syntax script for it either.
---@param filetype string
---@return integer?
local function workbench(filetype)
  local cached = benches[filetype]
  if cached == false then
    return nil
  end
  if cached ~= nil and vim.api.nvim_buf_is_valid(cached) then
    return cached
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("undolevels", -1, { buf = buf })

  local ok = vim.api.nvim_buf_call(buf, function()
    -- Source the syntax script by hand. Going through 'filetype' would run the
    -- FileType autocommands of the user's configuration, and language servers
    -- have no business attaching to a workbench.
    pcall(vim.cmd, "noautocmd setlocal filetype=" .. filetype)
    vim.b.current_syntax = nil
    pcall(vim.cmd, "runtime! syntax/" .. filetype .. ".vim")
    return vim.b.current_syntax ~= nil
  end)

  if not ok then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    benches[filetype] = false
    return nil
  end

  benches[filetype] = buf
  return buf
end

---Bytes the character starting at `index` occupies, so runs never split one.
local function char_length(text, index)
  local length = 1
  local byte = text:byte(index + 1)
  while byte ~= nil and byte >= 0x80 and byte < 0xC0 do
    length = length + 1
    byte = text:byte(index + length)
  end
  return length
end

---Read the highlighting Vim's syntax engine computes for part of a region and
---copy it onto the composite buffer. Used for the filetypes Tree-sitter has no
---parser for, which is most of what a repository holds besides its source.
---@param buf integer
---@param region diffbuf.SyntaxRegion
---@param token string Identifies the render, so a stale workbench is reloaded.
---@param from_row integer First line inside the region, 1-based.
---@param to_row integer Last line inside the region.
local function highlight_legacy(buf, region, token, from_row, to_row)
  local bench = workbench(region.filetype)
  if bench == nil then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, region.first - 1, region.last, false)
  local identity = ("%s:%d:%d"):format(token, region.first, #lines)
  if loaded[region.filetype] ~= identity then
    vim.api.nvim_buf_set_lines(bench, 0, -1, false, lines)
    loaded[region.filetype] = identity
  end

  local names = {}
  local offset = region.first - 2

  local function emit(row, from, to, group)
    if group == nil or group == "" then
      return
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, namespace, offset + row, from - 1, {
      end_col = to - 1,
      hl_group = group,
      priority = base_priority,
      strict = false,
    })
  end

  vim.api.nvim_buf_call(bench, function()
    for row = from_row, math.min(to_row, #lines) do
      local text = lines[row]
      local length = #text
      local column = 1
      local run_start, run_group = 1, nil

      while column <= length do
        local id = vim.fn.synID(row, column, 1)
        local name = ""
        if id ~= 0 then
          name = names[id]
          if name == nil then
            -- The item's own group carries the colorscheme's link; fall back to
            -- what it resolves to when the item is unnamed.
            name = vim.fn.synIDattr(id, "name")
            if name == "" then
              name = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
            end
            names[id] = name
          end
        end

        if name ~= run_group then
          emit(row, run_start, column, run_group)
          run_start, run_group = column, name
        end
        column = column + char_length(text, column)
      end

      emit(row, run_start, length + 1, run_group)
    end
  end)
end

---Highlight the regions this window can see, once each.
---@param buf integer
---@param win integer
function M.update(buf, win)
  local entry = buffers[buf]
  if entry == nil or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end

  local top = math.max(1, vim.fn.line("w0", win) - margin)
  local bottom = vim.fn.line("w$", win) + margin

  for index, region in ipairs(entry.regions) do
    if region.first <= bottom and region.last >= top then
      if region.lang ~= nil then
        if entry.done[index] == nil then
          entry.done[index] = true
          highlight_region(buf, region)
        end
      else
        -- Vim's syntax engine is walked in chunks, because reading it back costs
        -- a call per character.
        local from = math.max(region.first, top) - region.first
        local to = math.min(region.last, bottom) - region.first
        for chunk = math.floor(from / legacy_chunk_lines), math.floor(to / legacy_chunk_lines) do
          local key = ("%d:%d"):format(index, chunk)
          if entry.done[key] == nil then
            entry.done[key] = true
            highlight_legacy(
              buf,
              region,
              entry.token,
              chunk * legacy_chunk_lines + 1,
              (chunk + 1) * legacy_chunk_lines
            )
          end
        end
      end
    end
  end
end

local function watch(buf)
  if watchers[buf] ~= nil then
    return
  end

  watchers[buf] = vim.api.nvim_create_autocmd(
    { "WinScrolled", "WinResized", "CursorMoved", "BufWinEnter" },
    {
      buffer = buf,
      desc = "Highlight the part of the diffbuf.nvim diff that came into view",
      callback = function()
        local win = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
          M.update(buf, win)
        end
      end,
    }
  )

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer = buf,
    desc = "Release diffbuf.nvim syntax state",
    callback = function()
      M.detach(buf)
    end,
  })
end

---Drop every highlight and the region map.
---@param buf integer
function M.clear(buf)
  buffers[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  end
end

---@param buf integer
function M.detach(buf)
  M.clear(buf)
  watchers[buf] = nil
end

---Map a freshly rendered diff, then colour what is already on screen.
---@param buf integer
function M.render(buf)
  M.clear(buf)

  local state = State.get(buf)
  if state == nil or not Config.get().syntax then
    return
  end

  buffers[buf] = {
    regions = build_regions(state.rows),
    done = {},
    token = ("%d:%d"):format(buf, state.render_tick or 0),
  }
  watch(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    M.update(buf, win)
  end
end

M.namespace = namespace
return M
