local M = {}

local function read_lines(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  return vim.fn.readfile(path)
end

local function is_dir(path)
  return path and vim.fn.isdirectory(path) == 1
end

--- Re-find a bookmark after the file has been edited.
--- ok: line text still matches. reattached: same text, new line. stale/missing: unchanged lnum.
--- Directories are always considered ok (no line text).
function M.resolve(entry)
  if is_dir(entry.path) then
    entry.stale = false
    return entry, "ok"
  end
  local lines = read_lines(entry.path)
  if not lines then
    entry.stale = true
    return entry, "missing"
  end
  local current = lines[entry.lnum]
  if entry.line_text == "" or current == entry.line_text then
    entry.stale = false
    if entry.line_text == "" and current then
      entry.line_text = current
    end
    return entry, "ok"
  end
  local best, best_dist
  for i, line in ipairs(lines) do
    if line == entry.line_text then
      local dist = math.abs(i - entry.lnum)
      if not best or dist < best_dist then
        best = i
        best_dist = dist
      end
    end
  end
  if best then
    entry.lnum = best
    entry.stale = false
    return entry, "reattached"
  end
  entry.stale = true
  return entry, "stale"
end

function M.capture_line_text(entry)
  if is_dir(entry.path) then
    entry.line_text = ""
    entry.stale = false
    return entry
  end
  local lines = read_lines(entry.path)
  if not lines then
    entry.stale = true
    return entry
  end
  local line = lines[entry.lnum]
  if line == nil then
    entry.stale = true
    return entry
  end
  entry.line_text = line
  entry.stale = false
  return entry
end

return M