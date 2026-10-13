local M = {}

M.defaults = {
  -- nil uses stdpath("data")/oilmarks/bookmarks.lua
  save_path = nil,
  skip_confirm = false,
  prompt_on_select_if_modified = true,
  sign_text = "⚑",
  stale_sign_text = "!",
  float = {
    border = "rounded",
    width = 0.82,
    height = 0.62,
  },
  keymaps = {
    ["<CR>"] = "select",
    ["<C-v>"] = "select_vsplit",
    ["<C-s>"] = "select_split",
    ["p"] = "preview",
    ["-"] = "close",
    ["q"] = "close",
    ["g?"] = "help",
    ["r"] = "restore",
  },
}

---@type table|nil
M.values = nil

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.get()
  if not M.values then
    M.setup({})
  end
  return M.values
end

return M
