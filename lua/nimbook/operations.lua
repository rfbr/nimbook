local state = require("nimbook.state")
local buf_sync = require("nimbook.render.buffer")
local renderer = require("nimbook.render")
local Cell = require("nimbook.notebook.cell")

local M = {}

--- Get the current buffer's notebook and cursor cell index
---@return nimbook.Notebook|nil, integer|nil
local function get_context()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return nil, nil
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1 -- 0-indexed
  local cell_idx = notebook:cell_at_line(line)
  return notebook, cell_idx
end

--- Re-render the current buffer's notebook
local function rerender()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if notebook then
    renderer.render(buf, notebook)
  end
end

--- Navigate to the start of a cell's editable content
---@param cell nimbook.Cell
local function jump_to_cell(cell)
  if not cell.buf_start then
    return
  end
  local start, _ = buf_sync.get_source_range(cell)
  -- Set cursor to first content line (1-indexed for API)
  vim.api.nvim_win_set_cursor(0, { start + 1, 0 })
end

-- Navigation --

function M.goto_next_cell()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  if cell_idx < #notebook.cells then
    jump_to_cell(notebook.cells[cell_idx + 1])
  end
end

function M.goto_prev_cell()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  if cell_idx > 1 then
    jump_to_cell(notebook.cells[cell_idx - 1])
  end
end

function M.goto_next_code_cell()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  for i = cell_idx + 1, #notebook.cells do
    if notebook.cells[i].cell_type == "code" then
      jump_to_cell(notebook.cells[i])
      return
    end
  end
end

function M.goto_prev_code_cell()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  for i = cell_idx - 1, 1, -1 do
    if notebook.cells[i].cell_type == "code" then
      jump_to_cell(notebook.cells[i])
      return
    end
  end
end

-- Cell operations --

function M.add_cell_below()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook then
    return
  end
  -- Sync current state before modifying
  buf_sync.sync_from_buffer(notebook, buf)
  local insert_at = (cell_idx or #notebook.cells) + 1
  local new_cell = Cell.new_code()
  notebook:insert_cell(insert_at, new_cell)
  rerender()
  jump_to_cell(new_cell)
  vim.bo[buf].modified = true
end

function M.add_cell_above()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook then
    return
  end
  buf_sync.sync_from_buffer(notebook, buf)
  local insert_at = cell_idx or 1
  local new_cell = Cell.new_code()
  notebook:insert_cell(insert_at, new_cell)
  rerender()
  jump_to_cell(new_cell)
  vim.bo[buf].modified = true
end

function M.delete_cell()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  if #notebook.cells <= 1 then
    vim.notify("nimbook: cannot delete the last cell", vim.log.levels.WARN)
    return
  end
  buf_sync.sync_from_buffer(notebook, buf)
  notebook:remove_cell(cell_idx)
  rerender()
  -- Jump to the cell that's now at this position (or the last cell)
  local target = math.min(cell_idx, #notebook.cells)
  jump_to_cell(notebook.cells[target])
  vim.bo[buf].modified = true
end

function M.toggle_cell_type()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  buf_sync.sync_from_buffer(notebook, buf)
  local cell = notebook.cells[cell_idx]
  if cell.cell_type == "code" then
    cell.cell_type = "markdown"
    cell.raw.cell_type = "markdown"
    -- Remove code-specific fields
    cell.raw.outputs = nil
    cell.raw.execution_count = nil
  else
    cell.cell_type = "code"
    cell.raw.cell_type = "code"
    -- Add code-specific fields
    cell.raw.outputs = cell.raw.outputs or {}
    cell.raw.execution_count = vim.NIL
  end
  rerender()
  jump_to_cell(cell)
  vim.bo[buf].modified = true
end

function M.move_cell_up()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx or cell_idx <= 1 then
    return
  end
  buf_sync.sync_from_buffer(notebook, buf)
  notebook:move_cell(cell_idx, cell_idx - 1)
  rerender()
  jump_to_cell(notebook.cells[cell_idx - 1])
  vim.bo[buf].modified = true
end

function M.move_cell_down()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx or cell_idx >= #notebook.cells then
    return
  end
  buf_sync.sync_from_buffer(notebook, buf)
  notebook:move_cell(cell_idx, cell_idx + 1)
  rerender()
  jump_to_cell(notebook.cells[cell_idx + 1])
  vim.bo[buf].modified = true
end

-- Output operations --

function M.toggle_output()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  local cell = notebook.cells[cell_idx]
  if cell.cell_type ~= "code" then
    return
  end
  cell.outputs_visible = not cell.outputs_visible
  renderer.redecorate(buf, notebook)
end

function M.toggle_all_outputs()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return
  end
  -- Determine target state: if any are visible, hide all; otherwise show all
  local any_visible = false
  for _, cell in ipairs(notebook.cells) do
    if cell.cell_type == "code" and cell.outputs_visible then
      any_visible = true
      break
    end
  end
  for _, cell in ipairs(notebook.cells) do
    if cell.cell_type == "code" then
      cell.outputs_visible = not any_visible
    end
  end
  renderer.redecorate(buf, notebook)
end

function M.clear_output()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  local cell = notebook.cells[cell_idx]
  cell:clear_outputs()
  renderer.redecorate(buf, notebook)
  vim.bo[buf].modified = true
end

function M.clear_all_outputs()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return
  end
  for _, cell in ipairs(notebook.cells) do
    cell:clear_outputs()
  end
  renderer.redecorate(buf, notebook)
  vim.bo[buf].modified = true
end

function M.output_expand()
  require("nimbook.ui.floating").show_current()
end

--- Play the first audio/video found in the current cell's outputs
function M.play_media()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  local cell = notebook.cells[cell_idx]
  if cell.cell_type ~= "code" then
    return
  end
  local outputs = cell:get_outputs()
  for _, output in ipairs(outputs) do
    if output.output_type == "execute_result" or output.output_type == "display_data" then
      local data = output.data or {}
      local html = data["text/html"]
      if html then
        if type(html) == "table" then
          html = table.concat(html)
        end
        if html:match("<audio") or html:match("<video") then
          local src = html:match('<source%s+src="([^"]*)"') or html:match('src="([^"]*)"')
          if src then
            M._play_data_uri(src)
            return
          end
        end
      end
    end
  end
  vim.notify("nimbook: no audio/video in this cell", vim.log.levels.WARN)
end

--- Decode a data URI and play via system audio player
---@param uri string Either a data URI or a file path
function M._play_data_uri(uri)
  local path
  if uri:match("^data:") then
    -- data:audio/x-wav;base64,<payload>
    local mime, b64 = uri:match("^data:([^;]+);base64,(.+)$")
    if not b64 then
      vim.notify("nimbook: unsupported data URI format", vim.log.levels.ERROR)
      return
    end
    local ok, base64 = pcall(require, "nimbook.util.base64")
    if not ok then
      return
    end
    local decoded = base64.decode(b64)
    local ext = (mime and mime:match("/([%w%-]+)$") or "wav"):gsub("x%-", "")
    path = vim.fn.tempname() .. "." .. ext
    local f = io.open(path, "wb")
    if not f then
      vim.notify("nimbook: failed to write temp audio file", vim.log.levels.ERROR)
      return
    end
    f:write(decoded)
    f:close()
  else
    path = uri
  end

  -- Find an available player
  local players = {
    { "mpv", { "--no-video", "--really-quiet", path } },
    { "ffplay", { "-nodisp", "-autoexit", "-loglevel", "quiet", path } },
    { "aplay", { path } },
    { "paplay", { path } },
    { "afplay", { path } },
  }
  for _, p in ipairs(players) do
    if vim.fn.executable(p[1]) == 1 then
      vim.fn.jobstart(vim.list_extend({ p[1] }, p[2]), { detach = true })
      vim.notify("nimbook: playing with " .. p[1], vim.log.levels.INFO)
      return
    end
  end
  vim.notify("nimbook: no audio player found (install mpv, ffplay, or aplay)", vim.log.levels.WARN)
end

-- Kernel operations --

--- Get or create the kernel manager for the current buffer
---@return nimbook.KernelManager|nil
local function get_kernel()
  local buf = vim.api.nvim_get_current_buf()
  return state.get_kernel(buf)
end

function M.kernel_start()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return
  end

  local KernelManager = require("nimbook.kernel")
  local km = KernelManager.new({
    on_output = function(msg_id, output)
      M._handle_output(buf, msg_id, output)
    end,
    on_status = function(new_status)
      vim.schedule(function()
        -- Redecorate to update status indicators
        if vim.api.nvim_buf_is_valid(buf) then
          renderer.redecorate(buf, notebook)
        end
      end)
    end,
  })

  state.set_kernel(buf, km)

  km:start(function(ok, err)
    vim.schedule(function()
      if ok then
        vim.notify("nimbook: kernel started", vim.log.levels.INFO)
      else
        vim.notify("nimbook: kernel start failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.kernel_restart()
  local km = get_kernel()
  if not km then
    vim.notify("nimbook: no kernel to restart", vim.log.levels.WARN)
    return
  end
  km:restart(function()
    vim.schedule(function()
      vim.notify("nimbook: kernel restarted", vim.log.levels.INFO)
    end)
  end)
end

function M.kernel_interrupt()
  local km = get_kernel()
  if not km then
    return
  end
  km:interrupt()
  vim.notify("nimbook: interrupt sent", vim.log.levels.INFO)
end

function M.kernel_shutdown()
  local km = get_kernel()
  if not km then
    return
  end
  km:shutdown(false, function()
    vim.schedule(function()
      vim.notify("nimbook: kernel shut down", vim.log.levels.INFO)
    end)
  end)
end

function M.kernel_attach()
  -- Look for existing connection files
  local runtime_dir = vim.fn.expand("~/.local/share/jupyter/runtime")
  local files = vim.fn.glob(runtime_dir .. "/kernel-*.json", false, true)
  if #files == 0 then
    vim.notify("nimbook: no running kernels found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(files, {
    prompt = "Select kernel to attach:",
    format_item = function(item)
      return vim.fn.fnamemodify(item, ":t")
    end,
  }, function(choice)
    if not choice then
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local notebook = state.get(buf)
    if not notebook then
      return
    end

    local KernelManager = require("nimbook.kernel")
    local km = KernelManager.new({
      on_output = function(msg_id, output)
        M._handle_output(buf, msg_id, output)
      end,
      on_status = function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            renderer.redecorate(buf, notebook)
          end
        end)
      end,
    })

    state.set_kernel(buf, km)

    km:attach(choice, function(ok, err)
      vim.schedule(function()
        if ok then
          vim.notify("nimbook: attached to kernel", vim.log.levels.INFO)
        else
          vim.notify("nimbook: attach failed: " .. (err or "unknown"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

--- Execute the current cell
function M.execute_cell()
  local buf = vim.api.nvim_get_current_buf()
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  local cell = notebook.cells[cell_idx]
  if cell.cell_type ~= "code" then
    return
  end

  local km = get_kernel()
  if not km or km.status == "disconnected" then
    vim.notify("nimbook: no kernel connected (use <leader>ns to start)", vim.log.levels.WARN)
    return
  end

  -- Sync buffer to get latest source
  buf_sync.sync_from_buffer(notebook, buf)
  local code = cell:get_source()
  if vim.trim(code) == "" then
    return
  end

  -- Clear previous outputs
  cell:clear_outputs()
  cell.outputs_visible = true
  -- Mark cell as running
  cell._executing = true
  cell._exec_start = vim.uv.hrtime() / 1e9
  renderer.redecorate(buf, notebook)

  km:execute(code, cell_idx, function(outputs, execution_count)
    vim.schedule(function()
      cell._executing = false
      cell:set_outputs(outputs)
      cell:set_execution_count(execution_count)
      if cell._exec_start then
        cell._exec_time = (vim.uv.hrtime() / 1e9) - cell._exec_start
        cell._exec_start = nil
      end
      if vim.api.nvim_buf_is_valid(buf) then
        renderer.redecorate(buf, notebook)
      end
    end)
  end)
end

--- Execute current cell and advance to next
function M.execute_and_advance()
  M.execute_cell()
  -- Move to next cell (or create one if at the end)
  local notebook, cell_idx = get_context()
  if not notebook or not cell_idx then
    return
  end
  if cell_idx < #notebook.cells then
    jump_to_cell(notebook.cells[cell_idx + 1])
  else
    M.add_cell_below()
  end
end

--- Execute all cells in order
function M.execute_all()
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    return
  end
  local km = state.get_kernel(buf)
  if not km or km.status == "disconnected" then
    vim.notify("nimbook: no kernel connected", vim.log.levels.WARN)
    return
  end

  buf_sync.sync_from_buffer(notebook, buf)

  for i, cell in ipairs(notebook.cells) do
    if cell.cell_type == "code" then
      local code = cell:get_source()
      if vim.trim(code) ~= "" then
        cell:clear_outputs()
        cell.outputs_visible = true
        cell._executing = true

        km:execute(code, i, function(outputs, execution_count)
          vim.schedule(function()
            cell._executing = false
            cell:set_outputs(outputs)
            cell:set_execution_count(execution_count)
            if vim.api.nvim_buf_is_valid(buf) then
              renderer.redecorate(buf, notebook)
            end
          end)
        end)
      end
    end
  end

  renderer.redecorate(buf, notebook)
end

--- Handle an output arriving from the kernel
---@param buf integer
---@param msg_id string
---@param output table
function M._handle_output(buf, msg_id, output)
  -- Live-update: immediately show streaming output
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local notebook = state.get(buf)
    if notebook then
      renderer.redecorate(buf, notebook)
    end
  end)
end

return M
