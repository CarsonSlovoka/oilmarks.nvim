local M = {}

local ID_PAT = "^%x%x%x%x%x%x%x%x$"

function M.is_id(text)
  return type(text) == "string" and text:match(ID_PAT) ~= nil
end

function M.split_fields(line)
  local fields = {}
  local rest = line
  while true do
    local tab = rest:find("\t", 1, true)
    if not tab then
      fields[#fields + 1] = rest
      break
    end
    fields[#fields + 1] = rest:sub(1, tab - 1)
    rest = rest:sub(tab + 1)
  end
  return fields
end

--- Parse one buffer line.
--- empty lines return { empty = true }.
--- A leading 8-hex id is identity. Extra tabs in the note are kept as spaces.
function M.parse_line(line, normalize_location)
  if line:match("^%s*$") then
    return { empty = true }
  end
  local fields = M.split_fields(line)
  local id, name, location, note
  if M.is_id(fields[1]) then
    id = fields[1]
    name = fields[2] or ""
    location = fields[3] or ""
    if #fields > 4 then
      local rest = { unpack(fields, 4) }
      note = table.concat(rest, " ")
    else
      note = fields[4] or ""
    end
  else
    name = fields[1] or ""
    location = fields[2] or ""
    if #fields > 3 then
      note = table.concat({ unpack(fields, 3) }, " ")
    else
      note = fields[3] or ""
    end
  end
  name = vim.trim(name)
  if name == "" then
    return nil, "empty name"
  end
  local path, lnum, col = normalize_location(location)
  if not path then
    return nil, "location must look like path:line"
  end
  return {
    id = id,
    name = name,
    path = path,
    lnum = lnum,
    col = col,
    note = vim.trim(note or ""),
  }
end

function M.format_line(entry, location)
  return string.format("%s\t%s\t%s\t%s", entry.id, entry.name, location, entry.note or "")
end

function M.parse_buffer(lines, normalize_location)
  local parsed = {}
  for i, line in ipairs(lines) do
    local item, err = M.parse_line(line, normalize_location)
    if not item then
      return nil, string.format("line %d: %s", i, err)
    end
    if not item.empty then
      item.lnum_buf = i
      parsed[#parsed + 1] = item
    end
  end
  return parsed
end

return M
