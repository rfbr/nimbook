local Cell = require("nimbook.notebook.cell")

local M = {}

--- Render a notebook into buffer lines and compute cell mappings
--- Buffer format:
---   Code cells: ```{language}\n{source}\n```
---   Markdown cells: {source} (plain text)
---   Cells separated by empty lines
---
---@param notebook nimbook.Notebook
---@return string[] lines Buffer lines to set
function M.notebook_to_lines(notebook)
  local lines = {}
  local language = notebook:get_language()

  for i, cell in ipairs(notebook.cells) do
    local start_line = #lines -- 0-indexed start

    if cell.cell_type == "code" then
      -- Opening fence
      lines[#lines + 1] = "```" .. language
      -- Source lines
      local display_lines = cell:get_display_lines()
      for _, dl in ipairs(display_lines) do
        lines[#lines + 1] = dl
      end
      -- Closing fence
      lines[#lines + 1] = "```"
    else
      -- Markdown/raw: plain source lines
      local display_lines = cell:get_display_lines()
      for _, dl in ipairs(display_lines) do
        lines[#lines + 1] = dl
      end
    end

    cell.buf_start = start_line
    cell.buf_end = #lines -- exclusive end (0-indexed)

    -- Separator between cells
    if i < #notebook.cells then
      lines[#lines + 1] = ""
    end
  end

  return lines
end

--- Sync buffer content back to notebook cells
--- Call this when the buffer has been edited to update cell sources
---@param notebook nimbook.Notebook
---@param buf integer Buffer handle
function M.sync_from_buffer(notebook, buf)
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  M.sync_from_lines(notebook, buf_lines)
end

--- Sync from a lines array (testable without a real buffer)
---@param notebook nimbook.Notebook
---@param buf_lines string[]
function M.sync_from_lines(notebook, buf_lines)
  for _, cell in ipairs(notebook.cells) do
    if cell.buf_start and cell.buf_end then
      local source_lines
      if cell.cell_type == "code" then
        -- Skip opening and closing fences
        local src_start = cell.buf_start + 1 -- skip ```python (0-indexed)
        local src_end = cell.buf_end - 1 -- skip ``` (exclusive, so -1 is last fence, -1 more is last content)
        source_lines = {}
        for j = src_start + 1, src_end do -- +1 for 1-indexed lua arrays
          source_lines[#source_lines + 1] = buf_lines[j]
        end
      else
        -- Markdown/raw: all lines in range
        source_lines = {}
        for j = cell.buf_start + 1, cell.buf_end do -- +1 for 1-indexed
          source_lines[#source_lines + 1] = buf_lines[j]
        end
      end

      if source_lines then
        local text = table.concat(source_lines, "\n")
        cell:set_source(text)
      end
    end
  end
end

--- Recompute cell line mappings after a buffer change
--- This re-parses the buffer to find fence markers and cell boundaries
---@param notebook nimbook.Notebook
---@param buf integer Buffer handle
function M.recompute_mappings(notebook, buf)
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  M.recompute_mappings_from_lines(notebook, buf_lines)
end

--- Recompute mappings from lines array
---@param notebook nimbook.Notebook
---@param buf_lines string[]
function M.recompute_mappings_from_lines(notebook, buf_lines)
  local cell_idx = 1
  local line_idx = 0 -- 0-indexed

  while cell_idx <= #notebook.cells and line_idx < #buf_lines do
    local cell = notebook.cells[cell_idx]
    local line = buf_lines[line_idx + 1] -- 1-indexed for Lua table

    if cell.cell_type == "code" then
      -- Expect opening fence
      if line:match("^```") then
        cell.buf_start = line_idx
        -- Find closing fence
        local end_idx = line_idx + 1
        while end_idx < #buf_lines do
          if buf_lines[end_idx + 1] == "```" then
            cell.buf_end = end_idx + 1 -- exclusive
            line_idx = end_idx + 1
            break
          end
          end_idx = end_idx + 1
        end
        if not cell.buf_end or cell.buf_end <= cell.buf_start then
          -- Malformed: closing fence not found, take rest of buffer
          cell.buf_end = #buf_lines
          line_idx = #buf_lines
        end
      end
    else
      -- Markdown/raw cell: content until next empty line or fence
      cell.buf_start = line_idx
      local end_idx = line_idx
      while end_idx < #buf_lines do
        local next_line = buf_lines[end_idx + 1]
        -- Check if this is a separator line (empty line between cells)
        -- or the start of a code fence
        if end_idx > line_idx then
          if next_line == "" and cell_idx < #notebook.cells then
            break
          end
          if next_line:match("^```") and cell_idx < #notebook.cells then
            break
          end
        end
        end_idx = end_idx + 1
      end
      cell.buf_end = end_idx
      line_idx = end_idx
    end

    -- Skip separator empty line
    if line_idx < #buf_lines and buf_lines[line_idx + 1] == "" then
      line_idx = line_idx + 1
    end

    cell_idx = cell_idx + 1
  end
end

--- Get the source lines range for a cell (the editable part, excluding fences)
---@param cell nimbook.Cell
---@return integer start_line 0-indexed inclusive
---@return integer end_line 0-indexed exclusive
function M.get_source_range(cell)
  if cell.cell_type == "code" then
    return cell.buf_start + 1, cell.buf_end - 1
  else
    return cell.buf_start, cell.buf_end
  end
end

return M
