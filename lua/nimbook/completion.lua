--- nvim-cmp completion source for nimbook
--- Provides kernel-powered tab completion in code cells via Jupyter's complete_request.
---
--- Usage in cmp config:
---   cmp.setup.filetype("ipynb", {
---     sources = { { name = "nimbook" } }
---   })
---
--- Or it auto-registers if nvim-cmp is available.
local state = require("nimbook.state")
local buf_sync = require("nimbook.render.buffer")

local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:get_debug_name()
  return "nimbook"
end

function source:is_available()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "ipynb" then
    return false
  end
  local km = state.get_kernel(buf)
  return km ~= nil and km.status ~= "disconnected"
end

function source:get_keyword_pattern()
  return [[\w\+\.\?\w*]]
end

function source:get_trigger_characters()
  return { ".", "(", "[" }
end

function source:complete(params, callback)
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  local km = state.get_kernel(buf)

  if not notebook or not km or km.status == "disconnected" then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- Determine which cell we're in and the code context
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1 -- 0-indexed
  local col = cursor[2]
  local cell_idx = notebook:cell_at_line(line)

  if not cell_idx then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local cell = notebook.cells[cell_idx]
  if cell.cell_type ~= "code" then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- Build the code context: all code from this cell up to cursor position
  buf_sync.sync_from_buffer(notebook, buf)
  local source_start, _ = buf_sync.get_source_range(cell)
  local lines_in_cell = vim.api.nvim_buf_get_lines(buf, source_start, line + 1, false)
  -- Adjust last line to cursor column
  if #lines_in_cell > 0 then
    lines_in_cell[#lines_in_cell] = lines_in_cell[#lines_in_cell]:sub(1, col)
  end
  local code = table.concat(lines_in_cell, "\n")
  local cursor_pos = #code

  -- Also prepend code from all previous code cells for context
  local preamble = {}
  for i = 1, cell_idx - 1 do
    local prev = notebook.cells[i]
    if prev.cell_type == "code" then
      preamble[#preamble + 1] = prev:get_source()
    end
  end
  if #preamble > 0 then
    local preamble_str = table.concat(preamble, "\n")
    cursor_pos = #preamble_str + 1 + cursor_pos -- +1 for joining \n
    code = preamble_str .. "\n" .. code
  end

  -- Send complete_request
  local messages = require("nimbook.kernel.messages")
  local msg = messages.complete_request(km.session, code, cursor_pos)
  local msg_id = msg.header.msg_id

  -- Set up reply handler
  km._pending[msg_id] = {
    on_reply = function(reply)
      km._pending[msg_id] = nil
      vim.schedule(function()
        local content = reply.content or {}
        if content.status ~= "ok" then
          callback({ items = {}, isIncomplete = false })
          return
        end

        local matches = content.matches or {}
        local cursor_start = content.cursor_start or 0
        local cursor_end = content.cursor_end or cursor_pos

        local items = {}
        for _, match in ipairs(matches) do
          items[#items + 1] = {
            label = match,
            kind = 6, -- Variable (generic)
            sortText = string.format("%05d", #items),
          }
        end

        callback({
          items = items,
          isIncomplete = #items >= 100, -- if many results, may be incomplete
        })
      end)
    end,
  }

  km.channels:send("shell", msg)

  -- Timeout after 3 seconds
  vim.defer_fn(function()
    if km._pending[msg_id] then
      km._pending[msg_id] = nil
      callback({ items = {}, isIncomplete = false })
    end
  end, 3000)
end

--- Register the source with nvim-cmp (if available)
function source.register()
  local ok, cmp = pcall(require, "cmp")
  if not ok then
    return false
  end
  cmp.register_source("nimbook", source.new())
  return true
end

return source
