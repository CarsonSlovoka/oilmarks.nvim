local model = require("oilmarks.model")

local M = {}

--- Diff a snapshot against parsed buffer lines.
--- A repeated id is a copy (new id), not a second edit of the same entry.
--- Ids missing from the buffer are returned as removed, in original order.
function M.apply(snapshot, parsed, new_id)
  local by_id = {}
  for _, entry in ipairs(snapshot) do
    by_id[entry.id] = entry
  end
  local seen = {}
  local next_entries = {}
  local summary = { created = 0, updated = 0, deleted = 0, copied = 0 }
  for _, item in ipairs(parsed) do
    local source = item.id and by_id[item.id] or nil
    if source and not seen[item.id] then
      seen[item.id] = true
      local entry = vim.deepcopy(source)
      local changed = entry.name ~= item.name
        or entry.path ~= item.path
        or entry.lnum ~= item.lnum
        or (entry.col or 1) ~= item.col
        or (entry.note or "") ~= item.note
      entry.name = item.name
      entry.path = item.path
      entry.lnum = item.lnum
      entry.col = item.col
      entry.note = item.note
      if changed then
        entry.updated = os.time()
        if not model.same_target(source, entry) then
          entry._location_changed = true
          entry.stale = false
        end
        summary.updated = summary.updated + 1
      end
      next_entries[#next_entries + 1] = entry
    else
      local entry = model.blank_entry({
        id = new_id(),
        name = item.name,
        path = item.path,
        lnum = item.lnum,
        col = item.col,
        note = item.note,
        line_text = source and source.line_text or "",
      })
      entry._location_changed = true
      if source then
        summary.copied = summary.copied + 1
      else
        summary.created = summary.created + 1
      end
      next_entries[#next_entries + 1] = entry
    end
  end
  local removed = {}
  for _, entry in ipairs(snapshot) do
    if not seen[entry.id] then
      removed[#removed + 1] = vim.deepcopy(entry)
      summary.deleted = summary.deleted + 1
    end
  end
  return next_entries, removed, summary
end

function M.summary_text(summary, mode)
  local verb = mode == "trash" and "purge" or "trash"
  return string.format(
    "create %d, copy %d, update %d, %s %d",
    summary.created,
    summary.copied,
    summary.updated,
    verb,
    summary.deleted
  )
end

function M.is_noop(summary)
  return summary.created == 0 and summary.copied == 0 and summary.updated == 0 and summary.deleted == 0
end

return M
