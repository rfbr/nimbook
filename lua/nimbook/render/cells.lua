local config = require("nimbook.config")

local M = {}

local ns = vim.api.nvim_create_namespace("nimbook_cells")

--- Build a horizontal border line that fills the window width
---@param left_char string Corner/tee character for the left
---@param right_char string Corner/tee character for the right
---@param label? string Text to embed in the border
---@param label_hl? string Highlight group for the label
---@param win? integer Window handle for width calculation
---@return table[] Virtual text chunks {{text, hl}, ...}
local function build_border_line(left_char, right_char, label, label_hl, win)
  local bc = config.border_chars()
  local width = vim.api.nvim_win_get_width(win or 0) - vim.fn.getwininfo(win or vim.api.nvim_get_current_win())[1].textoff
  local hl = "NimbookBorder"

  local chunks = {}
  local sw = vim.api.nvim_strwidth
  if label and #label > 0 then
    local prefix = left_char .. bc.horizontal .. " "
    local fill = math.max(1, width - sw(prefix) - sw(label) - 2)
    local suffix = " " .. string.rep(bc.horizontal, fill) .. right_char
    chunks[#chunks + 1] = { prefix, hl }
    chunks[#chunks + 1] = { label, label_hl or hl }
    chunks[#chunks + 1] = { suffix, hl }
  else
    local line = left_char .. string.rep(bc.horizontal, math.max(1, width - 2)) .. right_char
    chunks[#chunks + 1] = { line, hl }
  end
  return chunks
end

--- Build the header label for a cell
---@param cell nimbook.Cell
---@param language string
---@return string label
---@return string hl
local function build_cell_label(cell, language)
  local parts = {}
  local cfg = config.current.render

  if cell.cell_type == "code" then
    parts[#parts + 1] = language
    if cfg.show_execution_count then
      local ec = cell:get_execution_count()
      if ec then
        parts[#parts + 1] = "[" .. ec .. "]"
      end
    end
    if cfg.show_execution_time and cell._exec_time then
      local t = cell._exec_time
      if t < 1 then
        parts[#parts + 1] = string.format("%.0fms", t * 1000)
      elseif t < 60 then
        parts[#parts + 1] = string.format("%.1fs", t)
      else
        parts[#parts + 1] = string.format("%.0fm%.0fs", math.floor(t / 60), t % 60)
      end
    end
  else
    parts[#parts + 1] = cell.cell_type
  end

  return table.concat(parts, " "), "NimbookCellType"
end

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

--- Build status icon for a cell
---@param cell nimbook.Cell
---@return string icon
---@return string hl
local function status_icon(cell)
  if cell.cell_type ~= "code" then
    return "", "NimbookBorder"
  end
  -- Running state
  if cell._executing then
    local frame_idx = math.floor((vim.uv.hrtime() / 1e8) % #spinner_frames) + 1
    return " " .. spinner_frames[frame_idx], "NimbookStatusRunning"
  end
  local ec = cell:get_execution_count()
  local outputs = cell:get_outputs()
  if #outputs > 0 then
    for _, out in ipairs(outputs) do
      if out.output_type == "error" then
        return " ✖", "NimbookStatusError"
      end
    end
    return " ✔", "NimbookStatusDone"
  elseif ec then
    return " ✔", "NimbookStatusDone"
  end
  return "", "NimbookBorder"
end

--- Render decorations for a single cell
---@param buf integer Buffer handle
---@param cell nimbook.Cell
---@param language string Notebook language
---@param win? integer Window handle
function M.render_cell(buf, cell, language, win)
  if not cell.buf_start or not cell.buf_end then
    return
  end

  local bc = config.border_chars()
  local label, label_hl = build_cell_label(cell, language)
  local icon, icon_hl = status_icon(cell)

  -- Compose full label with status
  local full_label = label
  if icon ~= "" then
    full_label = label .. icon
  end

  local is_code = cell.cell_type == "code"
  local content_start, content_end

  if is_code then
    -- Code cell: buf_start is ```python line, buf_end-1 is ``` line
    content_start = cell.buf_start + 1
    content_end = cell.buf_end - 2 -- last content line (0-indexed)

    -- Overlay the opening fence with top border
    local top_border = build_border_line(bc.top_left, bc.top_right, full_label, label_hl, win)
    -- Append status icon with its own highlight if present
    if icon ~= "" then
      -- Rebuild with separate icon highlight
      local base_label = label
      local prefix = bc.top_left .. bc.horizontal .. " "
      local width = vim.api.nvim_win_get_width(win or 0) - vim.fn.getwininfo(win or vim.api.nvim_get_current_win())[1].textoff
      local sw = vim.api.nvim_strwidth
      local suffix_len = math.max(1, width - sw(prefix) - sw(base_label) - sw(icon) - 2)
      local suffix = " " .. string.rep(bc.horizontal, suffix_len) .. bc.top_right
      top_border = {
        { prefix, "NimbookBorder" },
        { base_label, label_hl },
        { icon, icon_hl },
        { suffix, "NimbookBorder" },
      }
    end

    vim.api.nvim_buf_set_extmark(buf, ns, cell.buf_start, 0, {
      virt_text = top_border,
      virt_text_pos = "overlay",
      priority = 100,
    })

    -- Overlay the closing fence with bottom border (or output separator)
    local has_outputs = cell.outputs_visible and #cell:get_outputs() > 0
    local close_line = cell.buf_end - 1

    if has_outputs then
      local output_border = build_border_line(bc.tee_right, bc.tee_left, "output", "NimbookOutputBorder", win)
      vim.api.nvim_buf_set_extmark(buf, ns, close_line, 0, {
        virt_text = output_border,
        virt_text_pos = "overlay",
        priority = 100,
      })
    else
      local bottom_border = build_border_line(bc.bottom_left, bc.bottom_right, nil, nil, win)
      vim.api.nvim_buf_set_extmark(buf, ns, close_line, 0, {
        virt_text = bottom_border,
        virt_text_pos = "overlay",
        priority = 100,
      })
    end
  else
    -- Markdown cell: no fences in buffer, use virtual lines
    content_start = cell.buf_start
    content_end = cell.buf_end - 1

    -- Top border as virtual line above the first line
    local top_border = build_border_line(bc.top_left, bc.top_right, full_label, label_hl, win)
    vim.api.nvim_buf_set_extmark(buf, ns, cell.buf_start, 0, {
      virt_lines = { top_border },
      virt_lines_above = true,
      priority = 100,
    })

    -- Bottom border as virtual line below the last line
    local bottom_border = build_border_line(bc.bottom_left, bc.bottom_right, nil, nil, win)
    vim.api.nvim_buf_set_extmark(buf, ns, cell.buf_end - 1, 0, {
      virt_lines = { bottom_border },
      priority = 100,
    })
  end

  -- Side borders via inline virtual text for content lines
  local side_hl = is_code and "NimbookBorderCode" or "NimbookBorderMarkdown"
  for line = content_start, content_end do
    if line >= 0 and line < vim.api.nvim_buf_line_count(buf) then
      vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
        virt_text = { { bc.vertical .. " ", side_hl } },
        virt_text_pos = "inline",
        priority = 100,
      })
    end
  end
end

--- Render output virtual lines below a code cell
---@param buf integer
---@param cell nimbook.Cell
---@param cell_idx? integer Cell index for image tracking
---@param win? integer
function M.render_outputs(buf, cell, cell_idx, win)
  if cell.cell_type ~= "code" then
    return
  end
  if not cell.outputs_visible or not cell.buf_end then
    return
  end

  local outputs = cell:get_outputs()
  if #outputs == 0 then
    return
  end

  local bc = config.border_chars()
  local max_lines = config.current.render.output_max_lines
  local virt_lines = {}
  local total_text_lines = 0

  for _, output in ipairs(outputs) do
    -- Check for image outputs first
    local image_virt = M._try_render_image(buf, cell_idx or 0, output, win)
    if image_virt then
      for _, vl in ipairs(image_virt) do
        -- Prepend border (copy to avoid mutating cached virt_lines)
        local bordered = { { bc.vertical .. " ", "NimbookOutputBorder" } }
        for _, chunk in ipairs(vl) do
          bordered[#bordered + 1] = chunk
        end
        virt_lines[#virt_lines + 1] = bordered
      end
    else
      -- Text output with ANSI color support
      local chunks_list = M._output_to_chunks(output)
      for _, chunks in ipairs(chunks_list) do
        total_text_lines = total_text_lines + 1
        if total_text_lines <= max_lines then
          local line_chunks = { { bc.vertical .. " ", "NimbookOutputBorder" } }
          for _, chunk in ipairs(chunks) do
            line_chunks[#line_chunks + 1] = chunk
          end
          virt_lines[#virt_lines + 1] = line_chunks
        end
      end
    end
  end

  -- Add fold indicator if truncated
  if total_text_lines > max_lines then
    local remaining = total_text_lines - max_lines
    virt_lines[#virt_lines + 1] = {
      { bc.vertical .. " ", "NimbookOutputBorder" },
      { "... " .. remaining .. " more lines (press <leader>ne to expand)", "NimbookOutputFolded" },
    }
  end

  -- Bottom border after outputs
  local width = vim.api.nvim_win_get_width(win or 0) - vim.fn.getwininfo(win or vim.api.nvim_get_current_win())[1].textoff
  local bottom = bc.bottom_left .. string.rep(bc.horizontal, math.max(1, width - 2)) .. bc.bottom_right
  virt_lines[#virt_lines + 1] = { { bottom, "NimbookBorder" } }

  -- Attach virtual lines below the closing fence line
  local close_line = cell.buf_end - 1
  if close_line >= 0 and close_line < vim.api.nvim_buf_line_count(buf) then
    vim.api.nvim_buf_set_extmark(buf, ns, close_line, 0, {
      virt_lines = virt_lines,
      priority = 90,
    })
  end
end

--- Try to render an image output using terminal graphics.
--- Results are cached on the output table so that redecorates don't
--- re-transmit image data to the terminal (which causes flicker).
---@param buf integer
---@param cell_idx integer
---@param output table
---@param win? integer
---@return table[]|nil virt_lines Image virtual lines, or nil if not an image
function M._try_render_image(buf, cell_idx, output, win)
  if output.output_type ~= "execute_result" and output.output_type ~= "display_data" then
    return nil
  end

  local data = output.data or {}
  local image_b64 = data["image/png"] or data["image/jpeg"]
  if not image_b64 then
    return nil
  end

  -- Return cached result if the window width hasn't changed
  local win_width = vim.api.nvim_win_get_width(win or 0)
  if output._nimbook_img and output._nimbook_img.win_width == win_width then
    return output._nimbook_img.virt_lines
  end

  if type(image_b64) == "table" then
    image_b64 = table.concat(image_b64)
  end

  -- Decode base64
  local ok_b64, base64 = pcall(require, "nimbook.util.base64")
  if not ok_b64 then
    return nil
  end
  local ok_decode, image_data = pcall(base64.decode, image_b64)
  if not ok_decode or #image_data == 0 then
    return nil
  end

  -- Get the graphics renderer
  local ok_gfx, gfx_init = pcall(require, "nimbook.graphics")
  if not ok_gfx then
    return nil
  end

  local renderer = gfx_init.get_renderer()
  if not renderer then
    return {
      { { "[Image: inline display requires Kitty, Ghostty, or WezTerm]", "NimbookOutputFolded" } },
    }
  end

  -- Clean up previous placement if re-rendering at a new size
  if output._nimbook_img and output._nimbook_img.placement then
    pcall(renderer.clear, output._nimbook_img.placement)
  end

  local ok_display, virt_lines = pcall(renderer.display, buf, cell_idx, image_data, {
    max_width = win_width - 6,
    max_height = 20,
  })

  if ok_display and virt_lines then
    output._nimbook_img = { virt_lines = virt_lines, win_width = win_width }
    return virt_lines
  end

  return {
    { { "[Image: rendering failed]", "NimbookOutputFolded" } },
  }
end

--- Convert a Jupyter output to virtual text chunks with ANSI color support
--- Each entry is an array of {text, hl_group} pairs for one line
---@param output table
---@return table[][] Array of chunk arrays, one per line
function M._output_to_chunks(output)
  local ansi = require("nimbook.util.ansi")
  local result = {}

  if output.output_type == "stream" then
    local text = output.text
    if type(text) == "table" then
      text = table.concat(text)
    end
    local default_hl = (output.name == "stderr") and "NimbookOutputStderr" or "NimbookOutputStdout"
    for line in (text):gmatch("([^\n]*)\n?") do
      if line ~= "" or #result > 0 then
        result[#result + 1] = ansi.parse(line, default_hl)
      end
    end
    if #result > 0 and #result[#result] == 1 and result[#result][1][1] == "" then
      result[#result] = nil
    end

  elseif output.output_type == "execute_result" or output.output_type == "display_data" then
    local data = output.data or {}

    -- Check for HTML tables (render them nicely)
    local html = data["text/html"]
    if html and not (data["image/png"] or data["image/jpeg"]) then
      if type(html) == "table" then
        html = table.concat(html)
      end
      if html:match("<table") then
        local html_mod = require("nimbook.util.html")
        local text = html_mod.table_to_text(html)
        for line in text:gmatch("([^\n]*)") do
          result[#result + 1] = { { line, "NimbookOutputResult" } }
        end
        return result
      end
    end

    -- Fall back to text/plain
    local text = data["text/plain"]
    if text then
      if type(text) == "table" then
        text = table.concat(text)
      end
      for line in (text):gmatch("([^\n]*)\n?") do
        result[#result + 1] = { { line, "NimbookOutputResult" } }
      end
      if #result > 0 and #result[#result] == 1 and result[#result][1][1] == "" then
        result[#result] = nil
      end
    end

    -- Image outputs are handled by _try_render_image, not here

  elseif output.output_type == "error" then
    result[#result + 1] = { { output.ename .. ": " .. output.evalue, "NimbookOutputError" } }
    if output.traceback then
      for _, tb_line in ipairs(output.traceback) do
        for line in tb_line:gmatch("([^\n]*)") do
          if line ~= "" then
            result[#result + 1] = ansi.parse(line, "NimbookOutputError")
          end
        end
      end
    end
  end

  return result
end

--- Get highlight group for an output type
---@param output table
---@return string
function M._output_hl(output)
  if output.output_type == "stream" then
    if output.name == "stderr" then
      return "NimbookOutputStderr"
    end
    return "NimbookOutputStdout"
  elseif output.output_type == "execute_result" then
    return "NimbookOutputResult"
  elseif output.output_type == "error" then
    return "NimbookOutputError"
  end
  return "NimbookOutput"
end

--- Clear all cell decorations
---@param buf integer
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

--- Get the namespace ID
---@return integer
function M.get_namespace()
  return ns
end

return M
