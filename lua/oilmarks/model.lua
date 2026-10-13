local M = {}

local seq = 0

function M.new_id(existing)
  existing = existing or {}
  for _ = 1, 16 do
    seq = seq + 1
    local mixed = os.time() + seq * 131 + (vim.uv and vim.uv.hrtime() or 0)
    local id = string.format("%08x", mixed % 0x100000000)
    if not existing[id] then
      return id
    end
  end
  seq = seq + 1
  return string.format("%08x", seq)
end

function M.display_path(path)
  if not path or path == "" then
    return ""
  end
  return vim.fn.fnamemodify(path, ":~")
end

function M.display_location(entry)
  local loc = string.format("%s:%d", M.display_path(entry.path), entry.lnum or 1)
  if entry.col and entry.col > 1 then
    loc = loc .. ":" .. entry.col
  end
  return loc
end

--- Absolute path plus line/col. Location is parsed from the right so Windows
--- drive letters survive. Returns nil if the line number is missing.
function M.normalize_location(text)
  if not text or vim.trim(text) == "" then
    return nil
  end
  text = vim.trim(text)
  local path, lnum, col = text:match("^(.*):(%d+):(%d+)$")
  if not path then
    path, lnum = text:match("^(.*):(%d+)$")
    col = "1"
  end
  if not path or path == "" then
    return nil
  end
  local expanded = vim.fn.expand(path)
  local absolute = vim.fn.fnamemodify(expanded, ":p")
  if absolute == "" then
    absolute = expanded
  end
  return absolute, tonumber(lnum), tonumber(col) or 1
end

function M.blank_entry(fields)
  local now = os.time()
  return {
    id = fields.id,
    name = fields.name,
    path = fields.path,
    lnum = fields.lnum,
    col = fields.col or 1,
    note = fields.note or "",
    line_text = fields.line_text or "",
    stale = fields.stale or false,
    created = fields.created or now,
    updated = fields.updated or now,
  }
end

function M.same_target(a, b)
  return a.path == b.path and a.lnum == b.lnum and (a.col or 1) == (b.col or 1)
end

return M
