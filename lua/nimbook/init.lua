local M = {}

---@param opts? table
function M.setup(opts)
  require("nimbook.config").setup(opts)
  require("nimbook.render.highlights").setup()
end

--- Statusline components for integration with lualine, heirline, etc.
M.statusline = require("nimbook.ui.statusline")

return M
