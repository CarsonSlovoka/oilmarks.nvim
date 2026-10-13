local config = require("oilmarks.config")

local M = {}

M.cache = nil
M.mtime = nil
M.blocked = false
M.anchor_dirty = false

local function quote(value)
  return string.format("%q", value == nil and "" or tostring(value))
end

local function emit_entry(entry, indent)
  local pad = indent .. "  "
  return table.concat({
    indent .. "{",
    pad .. "id = " .. quote(entry.id) .. ",",
    pad .. "name = " .. quote(entry.name) .. ",",
    pad .. "path = " .. quote(entry.path) .. ",",
    pad .. "lnum = " .. tostring(entry.lnum or 1) .. ",",
    pad .. "col = " .. tostring(entry.col or 1) .. ",",
    pad .. "note = " .. quote(entry.note or "") .. ",",
    pad .. "line_text = " .. quote(entry.line_text or "") .. ",",
    pad .. "stale = " .. tostring(entry.stale and true or false) .. ",",
    pad .. "created = " .. tostring(entry.created or os.time()) .. ",",
    pad .. "updated = " .. tostring(entry.updated or os.time()) .. ",",
    indent .. "}",
  }, "\n")
end

local function emit_list(list, indent)
  local parts = { indent .. "{" }
  parts[#parts + 1] = indent .. "  id = " .. quote(list.id) .. ","
  parts[#parts + 1] = indent .. "  name = " .. quote(list.name) .. ","
  parts[#parts + 1] = indent .. "  entries = {"
  for _, entry in ipairs(list.entries or {}) do
    parts[#parts + 1] = emit_entry(entry, indent .. "    ") .. ","
  end
  parts[#parts + 1] = indent .. "  },"
  parts[#parts + 1] = indent .. "  trash = {"
  for _, entry in ipairs(list.trash or {}) do
    parts[#parts + 1] = emit_entry(entry, indent .. "    ") .. ","
  end
  parts[#parts + 1] = indent .. "  },"
  parts[#parts + 1] = indent .. "}"
  return table.concat(parts, "\n")
end

function M.serialize(data)
  local parts = {
    "-- oilmarks data. The oilmarks buffer is the supported editor.",
    "return {",
    "  version = 1,",
    "  lists = {",
  }
  for _, list in ipairs(data.lists or {}) do
    parts[#parts + 1] = emit_list(list, "    ") .. ","
  end
  parts[#parts + 1] = "  },"
  parts[#parts + 1] = "}"
  parts[#parts + 1] = ""
  return table.concat(parts, "\n")
end

function M.path()
  local configured = config.get().save_path
  if configured and configured ~= "" then
    return vim.fn.expand(configured)
  end
  return vim.fn.stdpath("data") .. "/oilmarks/bookmarks.lua"
end

local function empty_data()
  return {
    version = 1,
    lists = {
      {
        id = "root",
        name = "bookmarks",
        entries = {},
        trash = {},
      },
    },
  }
end

local function normalize(data)
  if type(data) ~= "table" then
    return nil, "bookmarks.lua did not return a table"
  end
  data.version = data.version or 1
  data.lists = data.lists or {}
  if #data.lists == 0 then
    data.lists[1] = { id = "root", name = "bookmarks", entries = {}, trash = {} }
  end
  for _, list in ipairs(data.lists) do
    list.entries = list.entries or {}
    list.trash = list.trash or {}
  end
  return data
end

local function file_mtime(path)
  local stat = vim.uv and vim.uv.fs_stat(path) or vim.loop.fs_stat(path)
  if not stat or not stat.mtime then
    return nil
  end
  return stat.mtime.sec
end

function M.load(force)
  if M.cache and not force then
    return M.cache
  end
  local path = M.path()
  if vim.fn.filereadable(path) == 0 then
    M.cache = empty_data()
    M.mtime = nil
    M.blocked = false
    return M.cache
  end
  local text = table.concat(vim.fn.readfile(path), "\n")
  local chunk, load_err = load(text, "@" .. path, "t")
  if not chunk then
    M.blocked = true
    return nil, load_err
  end
  if setfenv then
    setfenv(chunk, {})
  end
  local ok, data = pcall(chunk)
  if not ok then
    M.blocked = true
    return nil, data
  end
  local normalized, err = normalize(data)
  if not normalized then
    M.blocked = true
    return nil, err
  end
  M.cache = normalized
  M.mtime = file_mtime(path)
  M.blocked = false
  return M.cache
end

function M.root()
  local data, err = M.load()
  if not data then
    return nil, err
  end
  return data.lists[1]
end

function M.save(data)
  if M.blocked then
    return false, "bookmarks.lua failed to load; refusing to overwrite it"
  end
  local path = M.path()
  local mtime = file_mtime(path)
  if mtime and M.mtime and mtime > M.mtime then
    return false, "bookmarks.lua changed on disk; run :OilmarksReload"
  end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local tmp = path .. ".tmp"
  local payload = M.serialize(data)
  local fd, open_err = io.open(tmp, "w")
  if not fd then
    return false, open_err or "cannot write temp file"
  end
  fd:write(payload)
  fd:close()
  local renamed, rename_err = os.rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return false, rename_err or "rename failed"
  end
  M.cache = data
  M.mtime = file_mtime(path)
  M.anchor_dirty = false
  return true
end

function M.id_set()
  local ids = {}
  local data = M.load()
  if not data then
    return ids
  end
  for _, list in ipairs(data.lists) do
    for _, entry in ipairs(list.entries) do
      ids[entry.id] = true
    end
    for _, entry in ipairs(list.trash) do
      ids[entry.id] = true
    end
  end
  return ids
end

return M
