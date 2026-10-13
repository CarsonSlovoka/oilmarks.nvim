local actions = require("oilmarks.actions")
local config = require("oilmarks.config")
local signs = require("oilmarks.signs")

local M = {}

function M.setup(opts)
  config.setup(opts or {})
  local group = vim.api.nvim_create_augroup("oilmarks.signs", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      signs.refresh(ev.buf)
    end,
  })
  signs.refresh_all()
end

local function ready()
  if not config.values then
    M.setup({})
  end
end

function M.open(opts)
  ready()
  actions.open(opts)
end

function M.add(opts)
  ready()
  actions.add(opts)
end

function M.next()
  ready()
  actions.jump(1)
end

function M.prev()
  ready()
  actions.jump(-1)
end

function M.reload()
  actions.reload()
end

return M
