local buffer = require("nimbook.render.buffer")
local cells = require("nimbook.render.cells")

local M = {}

--- Full render: set buffer content and apply all decorations
---@param buf integer Buffer handle
---@param notebook nimbook.Notebook
---@param win? integer Window handle
function M.render(buf, notebook, win)
  -- Generate buffer lines from notebook
  local lines = buffer.notebook_to_lines(notebook)

  -- Set buffer content (temporarily make modifiable)
  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if not was_modifiable then
    vim.bo[buf].modifiable = was_modifiable
  end

  -- Buffer was just rewritten -- any tracked extmark IDs are now stale.
  -- Clear existing extmarks and reset per-cell mark tracking.
  cells.clear(buf)
  for _, cell in ipairs(notebook.cells) do
    cell._marks = nil
  end

  M.redecorate(buf, notebook, win)
end

--- Re-apply decorations without changing buffer content
--- Uses lazy rendering: only decorates cells in or near the visible viewport.
--- Updates extmarks in place using stable IDs stored on each cell -- avoids
--- the clear+readd flicker on incremental edits like 'o'.
---@param buf integer
---@param notebook nimbook.Notebook
---@param win? integer
function M.redecorate(buf, notebook, win)
  local language = notebook:get_language()

  -- Determine viewport for lazy rendering
  local top_line, bot_line = M._get_viewport(win)
  local margin = 50 -- render extra cells above/below viewport

  -- Render each cell's borders and outputs (only if near viewport)
  for i, cell in ipairs(notebook.cells) do
    if M._cell_in_range(cell, top_line - margin, bot_line + margin) then
      cells.render_cell(buf, cell, language, win)
      cells.render_outputs(buf, cell, i, win)
    end
  end
end

--- Get the visible viewport line range
---@param win? integer
---@return integer top 0-indexed
---@return integer bot 0-indexed
function M._get_viewport(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return 0, 100
  end
  local info = vim.fn.getwininfo(win)[1]
  if info then
    return info.topline - 1, info.botline - 1
  end
  return 0, vim.o.lines
end

--- Check if a cell overlaps with a line range
---@param cell nimbook.Cell
---@param range_top integer
---@param range_bot integer
---@return boolean
function M._cell_in_range(cell, range_top, range_bot)
  if not cell.buf_start or not cell.buf_end then
    return true -- render if no mapping yet
  end
  return cell.buf_end > range_top and cell.buf_start < range_bot
end

return M
