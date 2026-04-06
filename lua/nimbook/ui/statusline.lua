--- Statusline components for nimbook
--- Integrate with lualine, heirline, or any statusline that supports function components.
local state = require("nimbook.state")

local M = {}

local status_icons = {
  disconnected = "",
  starting = "⟳",
  idle = "●",
  busy = "◉",
}

local status_hl = {
  disconnected = "Comment",
  starting = "DiagnosticWarn",
  idle = "DiagnosticOk",
  busy = "DiagnosticWarn",
}

--- Get the kernel status string
---@return string
function M.kernel_status()
  local buf = vim.api.nvim_get_current_buf()
  local km = state.get_kernel(buf)
  if not km then
    return ""
  end
  local icon = status_icons[km.status] or ""
  return icon .. " " .. km.status
end

--- Get the kernel status highlight group
---@return string
function M.kernel_status_hl()
  local buf = vim.api.nvim_get_current_buf()
  local km = state.get_kernel(buf)
  if not km then
    return "Comment"
  end
  return status_hl[km.status] or "Comment"
end

--- Get the kernel name
---@return string
function M.kernel_name()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return ""
  end
  local ks = notebook.raw.metadata and notebook.raw.metadata.kernelspec
  if ks and ks.display_name then
    return ks.display_name
  end
  return notebook:get_language()
end

--- Get cell info for the current cursor position
---@return string
function M.cell_info()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return ""
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local cell_idx = notebook:cell_at_line(line)
  if not cell_idx then
    return ""
  end
  local cell = notebook.cells[cell_idx]
  return string.format("Cell %d/%d [%s]", cell_idx, #notebook.cells, cell.cell_type)
end

return M
