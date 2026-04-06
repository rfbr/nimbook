--- Cell folding for nimbook
--- Provides foldexpr and foldtext that fold on cell boundaries.
--- Code cells fold on the opening fence, markdown cells fold on the first line.
local state = require("nimbook.state")

local M = {}

--- Fold expression: called for each line by Neovim
--- Returns fold level string
---@return string
function M.foldexpr()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return "0"
  end

  local lnum = vim.v.lnum -- 1-indexed
  local line = lnum - 1   -- 0-indexed

  for _, cell in ipairs(notebook.cells) do
    if not cell.buf_start or not cell.buf_end then
      goto continue
    end

    if line == cell.buf_start then
      -- Start of cell = start of fold
      return ">1"
    end

    if line > cell.buf_start and line < cell.buf_end then
      -- Inside cell = fold level 1
      return "1"
    end

    ::continue::
  end

  -- Separator lines between cells
  return "0"
end

--- Custom fold text: shows a summary of the folded cell
---@return string
function M.foldtext()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return vim.fn.foldtext()
  end

  local fold_start = vim.v.foldstart - 1 -- 0-indexed
  local fold_end = vim.v.foldend - 1
  local num_lines = fold_end - fold_start + 1

  -- Find which cell this fold belongs to
  for _, cell in ipairs(notebook.cells) do
    if cell.buf_start and cell.buf_start == fold_start then
      local parts = {}

      if cell.cell_type == "code" then
        local lang = notebook:get_language()
        parts[#parts + 1] = "▸ " .. lang

        local ec = cell:get_execution_count()
        if ec then
          parts[#parts + 1] = "[" .. ec .. "]"
        end

        -- Show first line of code as preview
        local display = cell:get_display_lines()
        if #display > 0 then
          local preview = vim.trim(display[1])
          if #preview > 60 then
            preview = preview:sub(1, 57) .. "..."
          end
          parts[#parts + 1] = "│ " .. preview
        end

        -- Output status
        local outputs = cell:get_outputs()
        if #outputs > 0 then
          local has_error = false
          for _, out in ipairs(outputs) do
            if out.output_type == "error" then
              has_error = true
              break
            end
          end
          parts[#parts + 1] = has_error and "✖" or "✔"
        end
      elseif cell.cell_type == "markdown" then
        parts[#parts + 1] = "▸ markdown"

        local display = cell:get_display_lines()
        if #display > 0 then
          local preview = vim.trim(display[1])
          if #preview > 60 then
            preview = preview:sub(1, 57) .. "..."
          end
          parts[#parts + 1] = "│ " .. preview
        end
      else
        parts[#parts + 1] = "▸ " .. cell.cell_type
      end

      parts[#parts + 1] = "(" .. num_lines .. " lines)"
      return table.concat(parts, " ")
    end
  end

  return vim.fn.foldtext()
end

return M
