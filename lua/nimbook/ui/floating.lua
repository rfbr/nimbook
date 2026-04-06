--- Floating window for expanded output display
--- Shows full cell output in a scrollable floating window.
local state = require("nimbook.state")
local ansi = require("nimbook.util.ansi")

local M = {}

---@type integer|nil Currently open floating window
local float_win = nil
---@type integer|nil Buffer for the floating window
local float_buf = nil

--- Show expanded output for a cell in a floating window
---@param cell nimbook.Cell
function M.show_output(cell)
  if cell.cell_type ~= "code" then
    return
  end

  local outputs = cell:get_outputs()
  if #outputs == 0 then
    vim.notify("nimbook: no output to expand", vim.log.levels.INFO)
    return
  end

  -- Close any existing float
  M.close()

  -- Build output content
  local lines = {}
  local highlights = {} -- {line, chunks}

  for _, output in ipairs(outputs) do
    local output_lines = M._output_to_display(output)
    for _, entry in ipairs(output_lines) do
      lines[#lines + 1] = entry.text
      if entry.chunks then
        highlights[#lines] = entry.chunks
      end
    end
  end

  if #lines == 0 then
    return
  end

  -- Create buffer
  float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].bufhidden = "wipe"
  vim.bo[float_buf].filetype = "nimbook_output"

  -- Calculate window size
  local max_width = math.floor(vim.o.columns * 0.8)
  local max_height = math.floor(vim.o.lines * 0.7)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 2, max_width)
  local height = math.min(#lines, max_height)

  -- Center the window
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = M._build_title(cell),
    title_pos = "center",
  })

  -- Apply ANSI highlights
  local ns = vim.api.nvim_create_namespace("nimbook_float_hl")
  for line_idx, chunks in pairs(highlights) do
    local col_offset = 0
    for _, chunk in ipairs(chunks) do
      if chunk[2] and chunk[2] ~= "NimbookOutput" then
        vim.api.nvim_buf_set_extmark(float_buf, ns, line_idx - 1, col_offset, {
          end_col = col_offset + #chunk[1],
          hl_group = chunk[2],
        })
      end
      col_offset = col_offset + #chunk[1]
    end
  end

  -- Set up keymaps to close
  local close_keys = { "q", "<Esc>", "<C-c>" }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, function()
      M.close()
    end, { buffer = float_buf, silent = true })
  end

  -- Close on cursor leave
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = float_buf,
    once = true,
    callback = function()
      M.close()
    end,
  })
end

--- Build the window title from cell info
---@param cell nimbook.Cell
---@return string
function M._build_title(cell)
  local parts = { " Output" }
  local ec = cell:get_execution_count()
  if ec then
    parts[#parts + 1] = "[" .. ec .. "]"
  end
  parts[#parts + 1] = " "
  return table.concat(parts, " ")
end

--- Convert an output object to display lines with optional ANSI highlights
---@param output table
---@return table[] entries Array of { text: string, chunks?: table[] }
function M._output_to_display(output)
  local entries = {}

  if output.output_type == "stream" then
    local text = output.text
    if type(text) == "table" then
      text = table.concat(text)
    end
    for line in (text):gmatch("([^\n]*)\n?") do
      local chunks = ansi.parse(line, "NimbookOutputStdout")
      local plain = ansi.strip(line)
      if plain ~= "" or #entries > 0 then
        entries[#entries + 1] = { text = plain, chunks = chunks }
      end
    end
    -- Remove trailing empty entry
    if #entries > 0 and entries[#entries].text == "" then
      entries[#entries] = nil
    end

  elseif output.output_type == "execute_result" or output.output_type == "display_data" then
    local data = output.data or {}
    -- Prefer text/html for floating window (we can render it better)
    local html = data["text/html"]
    if html then
      if type(html) == "table" then
        html = table.concat(html)
      end
      -- Check if it's a table
      if html:match("<table") then
        local html_mod = require("nimbook.util.html")
        local text = html_mod.table_to_text(html)
        for line in text:gmatch("([^\n]*)") do
          entries[#entries + 1] = { text = line }
        end
      else
        local html_mod = require("nimbook.util.html")
        local text = html_mod.to_text(html)
        for line in text:gmatch("([^\n]*)") do
          entries[#entries + 1] = { text = line }
        end
      end
    else
      -- Fall back to text/plain
      local text = data["text/plain"]
      if text then
        if type(text) == "table" then
          text = table.concat(text)
        end
        for line in text:gmatch("([^\n]*)") do
          entries[#entries + 1] = { text = line }
        end
      end
    end

  elseif output.output_type == "error" then
    entries[#entries + 1] = { text = output.ename .. ": " .. output.evalue, chunks = { { output.ename .. ": " .. output.evalue, "NimbookOutputError" } } }
    if output.traceback then
      for _, tb_line in ipairs(output.traceback) do
        for line in tb_line:gmatch("([^\n]*)") do
          local chunks = ansi.parse(line, "NimbookOutputError")
          local plain = ansi.strip(line)
          if plain ~= "" then
            entries[#entries + 1] = { text = plain, chunks = chunks }
          end
        end
      end
    end
  end

  return entries
end

--- Close the floating window
function M.close()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_close(float_win, true)
  end
  float_win = nil
  float_buf = nil
end

--- Show output for the cell under cursor
function M.show_current()
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
  M.show_output(notebook.cells[cell_idx])
end

return M
