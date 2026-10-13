local store = require("oilmarks.store")

local M = {}

local ns = vim.api.nvim_create_namespace("oilmarks.signs")

local function define()
  local cfg = require("oilmarks.config").get()
  vim.fn.sign_define("OilmarksSign", {
    text = cfg.sign_text,
    texthl = "OilmarksSign",
  })
  vim.fn.sign_define("OilmarksStale", {
    text = cfg.stale_sign_text,
    texthl = "OilmarksStale",
  })
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].filetype == "oilmarks" or vim.bo[bufnr].buftype ~= "" then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  local path = vim.fn.fnamemodify(name, ":p")
  pcall(define)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local root = store.root()
  if not root then
    return
  end
  for _, entry in ipairs(root.entries) do
    if entry.path == path and entry.lnum and entry.lnum > 0 then
      local sign = entry.stale and "OilmarksStale" or "OilmarksSign"
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, entry.lnum - 1, 0, {
        sign_text = require("oilmarks.config").get()[entry.stale and "stale_sign_text" or "sign_text"],
        sign_hl_group = sign,
        priority = 100,
      })
    end
  end
end

function M.refresh_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.refresh(bufnr)
    end
  end
end

return M
