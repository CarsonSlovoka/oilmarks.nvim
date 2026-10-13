local anchor = require("oilmarks.anchor")
local config = require("oilmarks.config")
local diff = require("oilmarks.diff")
local model = require("oilmarks.model")
local store = require("oilmarks.store")
local view = require("oilmarks.view")

local M = {}

local preview_win

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "oilmarks" })
end

local function ensure_root()
  local root, err = store.root()
  if not root then
    notify("cannot load bookmarks: " .. tostring(err), vim.log.levels.ERROR)
  end
  return root
end

local function refresh_changed(entries)
  for _, entry in ipairs(entries) do
    if entry._location_changed then
      anchor.capture_line_text(entry)
      entry._location_changed = nil
    end
  end
end

function M.help(mode)
  local lines = {
    "<CR> jump    <C-v> vsplit    <C-s> split    p preview    - / q close    :w save",
    "columns: name <Tab> location <Tab> note. id is concealed. empty lines ignored.",
    "dd then :w moves a bookmark to trash. a pasted id is a copy.",
  }
  if mode == "trash" then
    lines[3] = "r marks a row to restore. dd then :w purges it. both commit on :w."
  end
  notify(table.concat(lines, "\n"))
end

function M.close(bufnr)
  local info = view.state(bufnr)
  if not info then
    return
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  if info.float then
    vim.api.nvim_win_close(win, true)
    return
  end
  if info.prev_buf and vim.api.nvim_buf_is_valid(info.prev_buf) and info.prev_buf ~= bufnr then
    vim.api.nvim_win_set_buf(win, info.prev_buf)
  end
end

local function confirm_save(bufnr)
  if not config.get().prompt_on_select_if_modified or not vim.bo[bufnr].modified then
    return true
  end
  local choice = vim.fn.confirm("oilmarks has unsaved changes", "&Save\n&Discard\n&Cancel", 1)
  if choice == 1 then
    return M.save_buffer(bufnr)
  end
  return choice == 2
end

local function place(entry, how, info)
  local status
  entry, status = anchor.resolve(entry)
  if status == "reattached" then
    store.anchor_dirty = true
    local root = store.root()
    if root then
      for _, item in ipairs(root.entries) do
        if item.id == entry.id then
          item.lnum = entry.lnum
          item.stale = false
          item.updated = os.time()
        end
      end
    end
    local list_buf = view.find("list")
    if list_buf and root then
      local list_info = view.state(list_buf)
      view.render(list_buf, root.entries, { modified = true, restore = list_info and list_info.restore or {} })
    end
    notify("reattached to line " .. entry.lnum .. "; :w to persist")
  elseif status == "missing" then
    notify("missing file: " .. entry.path, vim.log.levels.WARN)
    return
  elseif status == "stale" then
    notify("stale bookmark, jumping to old line " .. entry.lnum, vim.log.levels.WARN)
  end
  if how == "vsplit" then
    vim.cmd("vsplit")
  elseif how == "split" then
    vim.cmd("split")
  elseif how == "current" and info.float and info.prev_win and vim.api.nvim_win_is_valid(info.prev_win) then
    vim.api.nvim_set_current_win(info.prev_win)
    local win = info.buf and vim.fn.bufwinid(info.buf) or -1
    if win ~= -1 then
      vim.api.nvim_win_close(win, false)
    end
  end
  vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
  pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, math.max((entry.col or 1) - 1, 0) })
  require("oilmarks.signs").refresh(0)
end

function M.select(bufnr, how)
  if not confirm_save(bufnr) then
    return
  end
  local info = view.state(bufnr)
  if not info or info.mode == "trash" then
    notify("trash rows are restored with r, not opened", vim.log.levels.WARN)
    return
  end
  local entry = view.entry_on_line(bufnr, vim.fn.line("."))
  if not entry then
    return
  end
  info.buf = bufnr
  place(entry, how, info)
end

function M.preview(bufnr)
  local info = view.state(bufnr)
  if not info or info.mode == "trash" then
    return
  end
  local entry = view.entry_on_line(bufnr, vim.fn.line("."))
  if not entry then
    return
  end
  entry = anchor.resolve(vim.deepcopy(entry))
  if vim.fn.filereadable(entry.path) == 0 then
    notify("missing file: " .. entry.path, vim.log.levels.WARN)
    return
  end
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_set_current_win(preview_win)
  else
    vim.cmd("botright 14split")
    preview_win = vim.api.nvim_get_current_win()
    vim.wo[preview_win].previewwindow = true
  end
  vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
  vim.bo.modifiable = false
  pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, 0 })
  vim.cmd("normal! zz")
  local origin = vim.fn.bufwinid(bufnr)
  if origin ~= -1 then
    vim.api.nvim_set_current_win(origin)
  end
end

function M.mark_restore(bufnr)
  local info = view.state(bufnr)
  if not info or info.mode ~= "trash" then
    return
  end
  local lnum = vim.fn.line(".")
  local entry = view.entry_on_line(bufnr, lnum)
  if not entry or not entry.id then
    return
  end
  info.restore = info.restore or {}
  info.restore[lnum] = entry.id
  vim.bo[bufnr].modified = true
  view.relayout(bufnr)
  notify("marked for restore; :w to commit")
end

function M.save_buffer(bufnr)
  local info = view.state(bufnr)
  if not info then
    return false
  end
  local parsed, err = view.parse(bufnr)
  if not parsed then
    notify(err, vim.log.levels.ERROR)
    return false
  end
  local root = ensure_root()
  if not root then
    return false
  end
  local data = store.load()
  local ids = store.id_set()
  if info.mode == "trash" then
    local next_trash, _, summary = diff.apply(info.snapshot or {}, parsed, function()
      local id = model.new_id(ids)
      ids[id] = true
      return id
    end)
    refresh_changed(next_trash)
    local restore_ids = {}
    for _, id in pairs(info.restore or {}) do
      restore_ids[id] = true
    end
    local kept, restored = {}, {}
    for _, entry in ipairs(next_trash) do
      if restore_ids[entry.id] then
        restored[#restored + 1] = entry
      else
        kept[#kept + 1] = entry
      end
    end
    if not config.get().skip_confirm and (summary.deleted > 0 or #restored > 0 or summary.created > 0) then
      local text = string.format("restore %d, purge %d, create %d. Write?", #restored, summary.deleted, summary.created)
      if vim.fn.confirm(text, "&Write\n&Cancel", 1) ~= 1 then
        return false
      end
    end
    for _, entry in ipairs(restored) do
      root.entries[#root.entries + 1] = entry
    end
    root.trash = kept
    local ok, save_err = store.save(data)
    if not ok then
      notify(save_err, vim.log.levels.ERROR)
      return false
    end
    view.render(bufnr, root.trash, { modified = false, restore = {} })
    notify("trash saved")
    require("oilmarks.signs").refresh_all()
    return true
  end

  local next_entries, removed, summary = diff.apply(info.snapshot or {}, parsed, function()
    local id = model.new_id(ids)
    ids[id] = true
    return id
  end)
  refresh_changed(next_entries)
  if diff.is_noop(summary) and not store.anchor_dirty then
    vim.bo[bufnr].modified = false
    return true
  end
  if not config.get().skip_confirm and not diff.is_noop(summary) then
    local text = diff.summary_text(summary, "list") .. ". Write?"
    if vim.fn.confirm(text, "&Write\n&Cancel", 1) ~= 1 then
      return false
    end
  end
  for i = #removed, 1, -1 do
    table.insert(root.trash, 1, removed[i])
  end
  root.entries = next_entries
  local ok, save_err = store.save(data)
  if not ok then
    notify(save_err, vim.log.levels.ERROR)
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  view.render(bufnr, root.entries, { modified = false })
  pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  notify("saved " .. diff.summary_text(summary, "list"))
  require("oilmarks.signs").refresh_all()
  return true
end

function M.open(opts)
  opts = opts or {}
  local root = ensure_root()
  if not root then
    return
  end
  local mode = opts.trash and "trash" or "list"
  local existing = view.find(mode)
  if existing and vim.fn.bufwinid(existing) ~= -1 then
    vim.api.nvim_set_current_win(vim.fn.bufwinid(existing))
    return
  end
  local prev_win = vim.api.nvim_get_current_win()
  local prev_buf = vim.api.nvim_get_current_buf()
  local bufnr = existing or vim.api.nvim_create_buf(false, true)
  view.attach(bufnr, {
    mode = mode,
    float = opts.float and true or false,
    prev_win = prev_win,
    prev_buf = prev_buf,
    snapshot = {},
    restore = {},
  })
  view.open_window(bufnr, { float = opts.float, mode = mode })
  local entries = mode == "trash" and root.trash or root.entries
  view.render(bufnr, entries, { modified = mode == "list" and store.anchor_dirty or false })
end

function M.add(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
    notify("current buffer is not a file", vim.log.levels.WARN)
    return
  end
  local root = ensure_root()
  if not root then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p")
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
  local name = opts.name
  if not name or name == "" then
    name = vim.fn.fnamemodify(path, ":t") .. ":" .. cursor[1]
  end
  local note = opts.note
  if note == nil then
    note = vim.fn.input("Note: ")
  end
  local entry = model.blank_entry({
    id = model.new_id(store.id_set()),
    name = name,
    path = path,
    lnum = cursor[1],
    col = cursor[2] + 1,
    note = note,
    line_text = line,
  })
  root.entries[#root.entries + 1] = entry
  local ok, err = store.save(store.load())
  if not ok then
    root.entries[#root.entries] = nil
    notify(err, vim.log.levels.ERROR)
    return
  end
  local list_buf = view.find("list")
  if list_buf then
    view.render(list_buf, root.entries, { modified = false })
  end
  require("oilmarks.signs").refresh(bufnr)
  notify("added " .. model.display_location(entry))
end

function M.jump(dir)
  local root = ensure_root()
  if not root then
    return
  end
  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local best
  for _, entry in ipairs(root.entries) do
    if entry.path == path then
      local after = dir > 0 and entry.lnum > lnum or entry.lnum < lnum
      if after and (not best or (dir > 0 and entry.lnum < best.lnum) or (dir < 0 and entry.lnum > best.lnum)) then
        best = entry
      end
    end
  end
  if not best then
    for _, entry in ipairs(root.entries) do
      if entry.path == path and (not best or (dir > 0 and entry.lnum < best.lnum) or (dir < 0 and entry.lnum > best.lnum)) then
        best = entry
      end
    end
  end
  if not best then
    notify("no bookmarks in this file", vim.log.levels.WARN)
    return
  end
  place(best, "current", { float = false })
end

function M.reload()
  store.cache = nil
  local data, err = store.load(true)
  if not data then
    notify("reload failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  notify("reloaded bookmarks.lua")
  require("oilmarks.signs").refresh_all()
end

return M
