--- Cell text objects for nimbook
--- Provides `ic` (inner cell) and `ac` (around cell) motions.
--- `ic` selects the source content of the cell (excluding fences for code cells).
--- `ac` selects the entire cell including fences and the separator line after it.
local state = require("nimbook.state")
local buf_sync = require("nimbook.render.buffer")

local M = {}

--- Select the inner cell (source content only, no fences)
function M.inner_cell()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1 -- 0-indexed
  local cell_idx = notebook:cell_at_line(line)
  if not cell_idx then
    return
  end

  local cell = notebook.cells[cell_idx]
  local start_line, end_line = buf_sync.get_source_range(cell)

  -- end_line is exclusive, so last content line is end_line - 1
  -- Enter visual line mode and select the range
  vim.cmd("normal! " .. (start_line + 1) .. "GV" .. (end_line) .. "G")
end

--- Select around the cell (including fences and trailing separator)
function M.around_cell()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local cell_idx = notebook:cell_at_line(line)
  if not cell_idx then
    return
  end

  local cell = notebook.cells[cell_idx]
  if not cell.buf_start or not cell.buf_end then
    return
  end

  local start_line = cell.buf_start -- 0-indexed inclusive
  local end_line = cell.buf_end - 1 -- 0-indexed inclusive (buf_end is exclusive)

  -- Include the separator line after the cell if it exists
  local total_lines = vim.api.nvim_buf_line_count(buf)
  if end_line + 1 < total_lines then
    local next_line = vim.api.nvim_buf_get_lines(buf, end_line + 1, end_line + 2, false)[1]
    if next_line == "" then
      end_line = end_line + 1
    end
  end

  vim.cmd("normal! " .. (start_line + 1) .. "GV" .. (end_line + 1) .. "G")
end

--- Register text objects as buffer-local keymaps
---@param buf integer
function M.setup(buf)
  local opts = { buffer = buf, silent = true }

  -- Operator-pending and visual mode mappings
  for _, mode in ipairs({ "o", "x" }) do
    vim.keymap.set(mode, "ic", function()
      M.inner_cell()
    end, vim.tbl_extend("force", opts, { desc = "Nimbook: inner cell" }))

    vim.keymap.set(mode, "ac", function()
      M.around_cell()
    end, vim.tbl_extend("force", opts, { desc = "Nimbook: around cell" }))
  end
end

return M
