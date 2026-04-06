--- Kernel-powered hover/inspect documentation
--- Shows documentation for the symbol under cursor via Jupyter's inspect_request.
local state = require("nimbook.state")
local buf_sync = require("nimbook.render.buffer")
local ansi = require("nimbook.util.ansi")

local M = {}

--- Inspect the symbol under cursor and show docs in a floating window
function M.hover()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  local km = state.get_kernel(buf)

  if not notebook or not km or km.status == "disconnected" then
    vim.notify("nimbook: no kernel connected", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local col = cursor[2]
  local cell_idx = notebook:cell_at_line(line)

  if not cell_idx then
    return
  end

  local cell = notebook.cells[cell_idx]
  if cell.cell_type ~= "code" then
    return
  end

  -- Build code context up to cursor
  buf_sync.sync_from_buffer(notebook, buf)
  local source_start, _ = buf_sync.get_source_range(cell)
  local lines_in_cell = vim.api.nvim_buf_get_lines(buf, source_start, line + 1, false)

  -- Get the word under cursor for context
  local current_line = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
  -- Extend col to end of current word
  local word_end = col
  while word_end < #current_line and current_line:sub(word_end + 1, word_end + 1):match("[%w_.]") do
    word_end = word_end + 1
  end

  if #lines_in_cell > 0 then
    lines_in_cell[#lines_in_cell] = current_line:sub(1, word_end)
  end
  local code = table.concat(lines_in_cell, "\n")
  local cursor_pos = #code

  -- Prepend previous cells for context
  local preamble = {}
  for i = 1, cell_idx - 1 do
    local prev = notebook.cells[i]
    if prev.cell_type == "code" then
      preamble[#preamble + 1] = prev:get_source()
    end
  end
  if #preamble > 0 then
    local preamble_str = table.concat(preamble, "\n")
    cursor_pos = #preamble_str + 1 + cursor_pos
    code = preamble_str .. "\n" .. code
  end

  -- Send inspect_request
  local messages = require("nimbook.kernel.messages")
  local msg = messages.inspect_request(km.session, code, cursor_pos, 0)
  local msg_id = msg.header.msg_id

  km._pending[msg_id] = {
    on_reply = function(reply)
      km._pending[msg_id] = nil
      vim.schedule(function()
        local content = reply.content or {}
        if content.status ~= "ok" or not content.found then
          vim.notify("nimbook: no documentation found", vim.log.levels.INFO)
          return
        end

        local data = content.data or {}
        local text = data["text/plain"]
        if not text then
          vim.notify("nimbook: no text documentation available", vim.log.levels.INFO)
          return
        end

        if type(text) == "table" then
          text = table.concat(text)
        end

        M._show_docs(text)
      end)
    end,
  }

  km.channels:send("shell", msg)

  -- Timeout
  vim.defer_fn(function()
    if km._pending[msg_id] then
      km._pending[msg_id] = nil
    end
  end, 5000)
end

--- Show documentation text in a floating window
---@param text string Documentation text (may contain ANSI codes)
function M._show_docs(text)
  -- Strip ANSI and split into lines
  local clean = ansi.strip(text)
  local lines = vim.split(clean, "\n", { plain = true })

  -- Trim trailing empty lines
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    lines[#lines] = nil
  end

  if #lines == 0 then
    return
  end

  -- Create buffer
  local doc_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(doc_buf, 0, -1, false, lines)
  vim.bo[doc_buf].modifiable = false
  vim.bo[doc_buf].bufhidden = "wipe"
  vim.bo[doc_buf].filetype = "nimbook_docs"

  -- Try to use Python syntax for docstrings
  pcall(vim.treesitter.start, doc_buf, "python")

  -- Size the window
  local max_width = math.floor(vim.o.columns * 0.7)
  local max_height = math.floor(vim.o.lines * 0.6)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 2, max_width)
  width = math.max(width, 40)
  local height = math.min(#lines, max_height)

  -- Position near cursor
  local win = vim.api.nvim_open_win(doc_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Documentation ",
    title_pos = "center",
  })

  -- Close keymaps
  for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = doc_buf, silent = true })
  end

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = doc_buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

return M
