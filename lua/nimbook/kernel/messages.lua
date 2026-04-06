--- Jupyter message type constructors
--- Creates properly structured request messages for each Jupyter message type.
local wire = require("nimbook.kernel.wire")

local M = {}

--- Create an execute_request message
---@param session string
---@param code string Code to execute
---@param opts? { silent?: boolean, store_history?: boolean, stop_on_error?: boolean }
---@return nimbook.wire.Message
function M.execute_request(session, code, opts)
  opts = opts or {}
  return {
    identities = {},
    header = wire.make_header("execute_request", session),
    parent_header = {},
    metadata = {},
    content = {
      code = code,
      silent = opts.silent or false,
      store_history = opts.store_history ~= false, -- default true
      user_expressions = {},
      allow_stdin = false,
      stop_on_error = opts.stop_on_error ~= false, -- default true
    },
    buffers = {},
  }
end

--- Create a kernel_info_request message
---@param session string
---@return nimbook.wire.Message
function M.kernel_info_request(session)
  return {
    identities = {},
    header = wire.make_header("kernel_info_request", session),
    parent_header = {},
    metadata = {},
    content = {},
    buffers = {},
  }
end

--- Create a complete_request message (tab completion)
---@param session string
---@param code string Code context
---@param cursor_pos integer Cursor position in code
---@return nimbook.wire.Message
function M.complete_request(session, code, cursor_pos)
  return {
    identities = {},
    header = wire.make_header("complete_request", session),
    parent_header = {},
    metadata = {},
    content = {
      code = code,
      cursor_pos = cursor_pos,
    },
    buffers = {},
  }
end

--- Create an inspect_request message (hover/help)
---@param session string
---@param code string Code context
---@param cursor_pos integer
---@param detail_level? integer 0 or 1
---@return nimbook.wire.Message
function M.inspect_request(session, code, cursor_pos, detail_level)
  return {
    identities = {},
    header = wire.make_header("inspect_request", session),
    parent_header = {},
    metadata = {},
    content = {
      code = code,
      cursor_pos = cursor_pos,
      detail_level = detail_level or 0,
    },
    buffers = {},
  }
end

--- Create an interrupt_request message
---@param session string
---@return nimbook.wire.Message
function M.interrupt_request(session)
  return {
    identities = {},
    header = wire.make_header("interrupt_request", session),
    parent_header = {},
    metadata = {},
    content = {},
    buffers = {},
  }
end

--- Create a shutdown_request message
---@param session string
---@param restart? boolean
---@return nimbook.wire.Message
function M.shutdown_request(session, restart)
  return {
    identities = {},
    header = wire.make_header("shutdown_request", session),
    parent_header = {},
    metadata = {},
    content = {
      restart = restart or false,
    },
    buffers = {},
  }
end

return M
