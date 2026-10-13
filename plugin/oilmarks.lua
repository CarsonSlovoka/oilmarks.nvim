if vim.g.loaded_oilmarks == 1 then
  return
end
vim.g.loaded_oilmarks = 1

local function hl(name, link)
  vim.api.nvim_set_hl(0, name, { default = true, link = link })
end

hl("OilmarksSign", "DiagnosticSignInfo")
hl("OilmarksStale", "DiagnosticSignWarn")
hl("OilmarksLocation", "Directory")
hl("OilmarksNote", "Comment")
hl("OilmarksStaleLine", "WarningMsg")
hl("OilmarksRestore", "DiffAdd")
hl("OilmarksPad", "NonText")

local function complete(arglead)
  local items = { "float", "trash" }
  local out = {}
  for _, item in ipairs(items) do
    if item:find(arglead, 1, true) == 1 then
      out[#out + 1] = item
    end
  end
  return out
end

vim.api.nvim_create_user_command("Oilmarks", function(opts)
  local float = opts.args:find("float") ~= nil
  local trash = opts.args:find("trash") ~= nil
  require("oilmarks").open({ float = float, trash = trash })
end, { nargs = "*", complete = complete, desc = "Open the oilmarks buffer" })

vim.api.nvim_create_user_command("OilmarksAdd", function()
  require("oilmarks").add()
end, { desc = "Bookmark the current line" })

vim.api.nvim_create_user_command("OilmarksNext", function()
  require("oilmarks").next()
end, { desc = "Jump to the next bookmark in this file" })

vim.api.nvim_create_user_command("OilmarksPrev", function()
  require("oilmarks").prev()
end, { desc = "Jump to the previous bookmark in this file" })

vim.api.nvim_create_user_command("OilmarksReload", function()
  require("oilmarks").reload()
end, { desc = "Reload bookmarks.lua from disk" })
