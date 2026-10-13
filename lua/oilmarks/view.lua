local config = require("oilmarks.config")
local model = require("oilmarks.model")
local parse = require("oilmarks.parse")

local M = {}

local ns = vim.api.nvim_create_namespace("oilmarks.layout")
local state = {}

local function get(bufnr)
  return state[bufnr]
end

function M.state(bufnr)
  return state[bufnr]
end

function M.find(mode)
  for bufnr, info in pairs(state) do
    if vim.api.nvim_buf_is_valid(bufnr) and (not mode or info.mode == mode) then
      return bufnr, info
    end
  end
end

local function field_spans(line)
  local spans = {}
  local start = 1
  while true do
    local tab = line:find("\t", start, true)
    if not tab then
      spans[#spans + 1] = { start, #line + 1 }
      break
    end
    spans[#spans + 1] = { start, tab }
    start = tab + 1
  end
  return spans
end

function M.relayout(bufnr)
  local info = get(bufnr)
  if not info or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local items = {}
  local name_w, loc_w = 12, 16
  for i, line in ipairs(lines) do
    local fields = parse.split_fields(line)
    local has_id = parse.is_id(fields[1] or "")
    local name = has_id and (fields[2] or "") or (fields[1] or "")
    local location = has_id and (fields[3] or "") or (fields[2] or "")
    name_w = math.max(name_w, vim.fn.strdisplaywidth(name))
    loc_w = math.max(loc_w, vim.fn.strdisplaywidth(location))
    items[i] = { has_id = has_id, name = name, location = location, spans = field_spans(line) }
  end
  name_w = math.min(name_w, 40)
  loc_w = math.min(loc_w, 48)
  for i, line in ipairs(lines) do
    local item = items[i]
    if item.has_id then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
        end_col = math.min(9, #line),
        conceal = "",
      })
    end
    local name_index = item.has_id and 2 or 1
    local loc_index = item.has_id and 3 or 2
    local note_index = item.has_id and 4 or 3
    local function pad_before(index, width, text)
      local span = item.spans[index]
      if not span then
        return
      end
      local gap = width - vim.fn.strdisplaywidth(text)
      if gap > 0 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, i - 1, span[2] - 1, {
          virt_text = { { string.rep(" ", gap), "OilmarksPad" } },
          virt_text_pos = "inline",
        })
      end
    end
    pad_before(name_index, name_w, item.name)
    pad_before(loc_index, loc_w, item.location)
    for _, span in ipairs(item.spans) do
      if span[2] <= #line and line:sub(span[2], span[2]) == "\t" then
        vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, span[2] - 1, {
          end_col = span[2],
          conceal = " ",
        })
      end
    end
    local loc_span = item.spans[loc_index]
    if loc_span then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, loc_span[1] - 1, {
        end_col = math.max(loc_span[1] - 1, loc_span[2] - 1),
        hl_group = "OilmarksLocation",
      })
    end
    local note_span = item.spans[note_index]
    if note_span and note_span[1] <= #line then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, note_span[1] - 1, {
        end_col = math.max(note_span[1], note_span[2] - 1),
        hl_group = "OilmarksNote",
      })
    end
    if info.restore and info.restore[i] then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, { line_hl_group = "OilmarksRestore" })
    end
  end
  if info.stale_lines then
    for lnum, _ in pairs(info.stale_lines) do
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, { line_hl_group = "OilmarksStaleLine" })
    end
  end
end

function M.render(bufnr, entries, opts)
  opts = opts or {}
  local info = get(bufnr)
  if not info then
    return
  end
  local lines = {}
  local stale_lines = {}
  for i, entry in ipairs(entries) do
    lines[i] = parse.format_line(entry, model.display_location(entry))
    if entry.stale then
      stale_lines[i] = true
    end
  end
  if #lines == 0 then
    lines[1] = ""
  end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  info.snapshot = vim.deepcopy(entries)
  info.stale_lines = stale_lines
  info.restore = opts.restore or {}
  M.relayout(bufnr)
  if opts.modified ~= nil then
    vim.bo[bufnr].modified = opts.modified
  end
end

function M.parse(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return parse.parse_buffer(lines, model.normalize_location)
end

local function entry_matches(entry, query)
  if not query or query == "" then
    return true
  end
  local q = query:lower()
  local hay = (entry.name or "") .. "\n" .. (entry.note or "") .. "\n" .. model.display_location(entry)
  return hay:lower():find(q, 1, true) ~= nil
end

local function current_entries(bufnr)
  local info = get(bufnr)
  if not info then
    return nil, "no state"
  end
  local parsed, err = M.parse(bufnr)
  if not parsed then
    return nil, err
  end
  local by_id = {}
  for _, entry in ipairs(info.snapshot or {}) do
    if entry.id then
      by_id[entry.id] = entry
    end
  end
  local entries = {}
  for _, item in ipairs(parsed) do
    local entry
    if item.id and by_id[item.id] then
      entry = vim.deepcopy(by_id[item.id])
      entry.name = item.name
      entry.path = item.path
      entry.lnum = item.lnum
      entry.col = item.col
      entry.note = item.note
    else
      entry = model.blank_entry(item)
    end
    entries[#entries + 1] = entry
  end
  return entries
end

local function set_winbar(bufnr, filter)
  local info = get(bufnr)
  if not info then
    return
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  local prefix = info.mode == "trash" and " oilmarks trash" or " oilmarks"
  if filter and filter ~= "" then
    vim.wo[win].winbar = prefix .. "  /" .. filter .. "    name    location    note"
  else
    vim.wo[win].winbar = prefix .. "    name    location    note"
  end
end

function M.clear_filter(bufnr)
  local info = get(bufnr)
  if not info or not info.filter or info.filter == "" then
    return
  end
  local was_modified = info.was_modified
  if vim.bo[bufnr].modified then
    vim.notify("filter cleared; edits made while filtered were discarded", vim.log.levels.WARN, { title = "oilmarks" })
  end
  info.filter = nil
  info.was_modified = nil
  local entries = info.unfiltered or {}
  info.unfiltered = nil
  M.render(bufnr, entries, { modified = was_modified })
  set_winbar(bufnr)
end

function M.start_filter(bufnr)
  local info = get(bufnr)
  if not info then
    return
  end
  if info.filter and info.filter ~= "" then
    M.clear_filter(bufnr)
    info = get(bufnr)
    if not info then
      return
    end
  end
  local entries, err = current_entries(bufnr)
  if not entries then
    vim.notify("cannot filter: " .. tostring(err), vim.log.levels.ERROR, { title = "oilmarks" })
    return
  end
  info.unfiltered = entries
  info.was_modified = vim.bo[bufnr].modified
  local query = ""
  local function apply()
    local filtered = {}
    for _, entry in ipairs(info.unfiltered) do
      if entry_matches(entry, query) then
        filtered[#filtered + 1] = entry
      end
    end
    M.render(bufnr, filtered, { modified = false })
    set_winbar(bufnr, query)
    vim.cmd("redraw")
  end
  apply()
  while true do
    local ok, char = pcall(vim.fn.getcharstr)
    if not ok or not char then
      break
    end
    if char == "\27" then
      query = ""
      break
    elseif char == "\r" or char == "\n" then
      break
    elseif char == "\8" or char == "\127" then
      query = query:sub(1, -2)
    elseif char == "\23" then
      query = ""
    else
      query = query .. char
    end
    apply()
  end
  if query == "" then
    M.render(bufnr, info.unfiltered, { modified = info.was_modified })
    info.unfiltered = nil
    info.was_modified = nil
    info.filter = nil
    set_winbar(bufnr)
  else
    info.filter = query
    set_winbar(bufnr, query)
  end
end

local function map(bufnr, lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true, silent = true, desc = desc })
end

local function jump_field(dir)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local spots = {}
  local start = 1
  while true do
    local tab = line:find("\t", start, true)
    if not tab then
      break
    end
    spots[#spots + 1] = tab + 1
    start = tab + 1
  end
  if dir > 0 then
    for _, spot in ipairs(spots) do
      if spot > col then
        vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), spot - 1 })
        return
      end
    end
  else
    for i = #spots, 1, -1 do
      if spots[i] < col then
        vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), spots[i] - 1 })
        return
      end
    end
  end
end

function M.attach(bufnr, info)
  state[bufnr] = info
  vim.api.nvim_buf_set_name(bufnr, info.mode == "trash" and "oilmarks://trash" or "oilmarks://bookmarks")
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].filetype = "oilmarks"
  vim.bo[bufnr].modifiable = true
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].conceallevel = 3
  vim.wo[win].concealcursor = "nvic"
  vim.wo[win].wrap = false
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winbar = info.mode == "trash" and " oilmarks trash    name    location    note" or " oilmarks    name    location    note"

  local aug = vim.api.nvim_create_augroup("oilmarks." .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = aug,
    buffer = bufnr,
    callback = function()
      M.relayout(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    callback = function()
      require("oilmarks.actions").save_buffer(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = aug,
    buffer = bufnr,
    callback = function()
      state[bufnr] = nil
    end,
  })

  local actions = function()
    return require("oilmarks.actions")
  end
  local keys = config.get().keymaps
  local handlers = {
    select = function()
      actions().select(bufnr, "current")
    end,
    select_vsplit = function()
      actions().select(bufnr, "vsplit")
    end,
    select_split = function()
      actions().select(bufnr, "split")
    end,
    preview = function()
      actions().preview(bufnr)
    end,
    close = function()
      actions().close(bufnr)
    end,
    help = function()
      actions().help(info.mode)
    end,
    restore = function()
      actions().mark_restore(bufnr)
    end,
  }
  for lhs, name in pairs(keys) do
    if handlers[name] then
      map(bufnr, lhs, handlers[name], "oilmarks " .. name)
    end
  end
  map(bufnr, "/", function()
    M.start_filter(bufnr)
  end, "oilmarks filter")
  map(bufnr, "<C-l>", function()
    M.clear_filter(bufnr)
  end, "oilmarks clear filter")
  vim.keymap.set("i", "<Tab>", function()
    jump_field(1)
  end, { buffer = bufnr, desc = "oilmarks next field" })
  vim.keymap.set("i", "<S-Tab>", function()
    jump_field(-1)
  end, { buffer = bufnr, desc = "oilmarks prev field" })
end

function M.open_window(bufnr, opts)
  opts = opts or {}
  if opts.float then
    local cfg = config.get().float
    local width = math.max(40, math.floor(vim.o.columns * cfg.width))
    local height = math.max(8, math.floor(vim.o.lines * cfg.height))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      border = cfg.border,
      title = opts.mode == "trash" and " oilmarks trash " or " oilmarks ",
      title_pos = "center",
      style = "minimal",
    })
  else
    vim.api.nvim_win_set_buf(0, bufnr)
  end
end

function M.entry_on_line(bufnr, lnum)
  local info = get(bufnr)
  if not info then
    return
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line then
    return
  end
  local item = parse.parse_line(line, model.normalize_location)
  if not item or item.empty then
    return
  end
  local snapshot = info.snapshot or {}
  local by_id = {}
  for _, entry in ipairs(snapshot) do
    by_id[entry.id] = entry
  end
  if item.id and by_id[item.id] then
    local entry = vim.deepcopy(by_id[item.id])
    entry.name = item.name
    entry.path = item.path
    entry.lnum = item.lnum
    entry.col = item.col
    entry.note = item.note
    return entry
  end
  return model.blank_entry(item)
end

return M
