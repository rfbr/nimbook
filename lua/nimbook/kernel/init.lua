--- KernelManager: manages kernel lifecycle, execution, and message routing.
local zmq = require("nimbook.kernel.zmq")
local Channels = require("nimbook.kernel.channels")
local messages = require("nimbook.kernel.messages")
local config = require("nimbook.config")
local util = require("nimbook.util")

---@class nimbook.KernelManager
---@field ctx nimbook.zmq.Context|nil
---@field channels nimbook.Channels|nil
---@field session string
---@field connection table|nil Parsed connection file
---@field process vim.SystemObj|nil Kernel process handle
---@field status "disconnected"|"starting"|"idle"|"busy"
---@field _pending table<string, nimbook.KernelCallback> msg_id -> callback
---@field _cell_map table<string, nimbook.CellExecState> msg_id -> cell execution state
---@field _on_output fun(msg_id: string, output: table)|nil Output callback
---@field _on_status fun(status: string)|nil Status change callback
---@field _connection_file string|nil Path to connection file
local KernelManager = {}
KernelManager.__index = KernelManager

---@class nimbook.KernelCallback
---@field on_reply fun(msg: nimbook.wire.Message)?
---@field on_output fun(output: table)?
---@field on_status fun(status: string)?

---@class nimbook.CellExecState
---@field cell_idx integer
---@field outputs table[]
---@field started_at number
---@field execution_count integer|nil
---@field reply_received boolean
---@field idle_received boolean
---@field on_done fun(outputs: table[], execution_count: integer|nil)|nil

--- Create a new KernelManager
---@param opts? { on_output?: fun(msg_id: string, output: table), on_status?: fun(status: string) }
---@return nimbook.KernelManager
function KernelManager.new(opts)
  opts = opts or {}
  local self = setmetatable({}, KernelManager)
  self.ctx = nil
  self.channels = nil
  self.session = util.uuid()
  self.connection = nil
  self.process = nil
  self.status = "disconnected"
  self._pending = {}
  self._cell_map = {}
  self._on_output = opts.on_output
  self._on_status = opts.on_status
  self._connection_file = nil
  return self
end

--- Start a new kernel process
---@param callback? fun(ok: boolean, err?: string)
function KernelManager:start(callback)
  if self.status ~= "disconnected" then
    if callback then callback(false, "kernel already running") end
    return
  end

  self:_set_status("starting")

  -- Generate connection file
  local conn = {
    transport = "tcp",
    ip = "127.0.0.1",
    shell_port = self:_find_port(),
    iopub_port = self:_find_port(),
    control_port = self:_find_port(),
    stdin_port = self:_find_port(),
    hb_port = self:_find_port(),
    key = util.uuid(),
    signature_scheme = "hmac-sha256",
    kernel_name = "python3",
  }

  -- Write connection file
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  self._connection_file = tmpdir .. "/kernel.json"
  local f = io.open(self._connection_file, "w")
  if not f then
    self:_set_status("disconnected")
    if callback then callback(false, "failed to write connection file") end
    return
  end
  f:write(vim.json.encode(conn))
  f:close()

  self.connection = conn

  -- Launch kernel process
  local python_cmd = config.current.kernel.python_cmd
  self.process = vim.system(
    { python_cmd, "-m", "ipykernel_launcher", "-f", self._connection_file },
    {
      detach = true,
      stdout = false,
      stderr = function(_, data)
        if data then
          -- Log kernel stderr for debugging
          vim.schedule(function()
            -- Only show errors, not routine startup messages
            if data:match("[Ee]rror") or data:match("[Ee]xception") then
              vim.notify("nimbook kernel: " .. vim.trim(data), vim.log.levels.DEBUG)
            end
          end)
        end
      end,
    }
  )

  -- Give the kernel a moment to bind ports, then connect
  vim.defer_fn(function()
    local ok, err = pcall(self._connect, self)
    if ok then
      -- Request kernel info to verify connection
      self:_request_kernel_info(function(success)
        if success then
          self:_set_status("idle")
          if callback then callback(true) end
        else
          self:_set_status("disconnected")
          if callback then callback(false, "kernel did not respond") end
        end
      end)
    else
      self:_set_status("disconnected")
      if callback then callback(false, tostring(err)) end
    end
  end, 1500) -- 1.5s startup delay
end

--- Connect to an existing kernel via connection file
---@param connection_file string Path to kernel connection JSON
---@param callback? fun(ok: boolean, err?: string)
function KernelManager:attach(connection_file, callback)
  if self.status ~= "disconnected" then
    if callback then callback(false, "already connected") end
    return
  end

  self:_set_status("starting")

  local f_conn = io.open(connection_file, "r")
  if not f_conn then
    self:_set_status("disconnected")
    if callback then callback(false, "cannot read connection file") end
    return
  end
  local content = f_conn:read("*a")
  f_conn:close()

  local ok_json, conn = pcall(vim.json.decode, content)
  if not ok_json then
    self:_set_status("disconnected")
    if callback then callback(false, "invalid connection file") end
    return
  end

  self.connection = conn
  self._connection_file = connection_file

  local ok_connect, err = pcall(self._connect, self)
  if not ok_connect then
    self:_set_status("disconnected")
    if callback then callback(false, tostring(err)) end
    return
  end

  self:_request_kernel_info(function(success)
    if success then
      self:_set_status("idle")
      if callback then callback(true) end
    else
      self:_set_status("disconnected")
      if callback then callback(false, "kernel did not respond") end
    end
  end)
end

--- Execute code and track outputs
---@param code string
---@param cell_idx integer
---@param on_done? fun(outputs: table[], execution_count: integer|nil)
---@return string msg_id
function KernelManager:execute(code, cell_idx, on_done)
  if self.status == "disconnected" or not self.channels then
    vim.notify("nimbook: no kernel connected", vim.log.levels.ERROR)
    return ""
  end

  local msg = messages.execute_request(self.session, code)
  local msg_id = msg.header.msg_id

  -- Track this execution. Completion requires both execute_reply (shell)
  -- and status:idle (iopub) to ensure all outputs have been received.
  self._cell_map[msg_id] = {
    cell_idx = cell_idx,
    outputs = {},
    started_at = vim.uv.hrtime() / 1e9,
    execution_count = nil,
    reply_received = false,
    idle_received = false,
    on_done = on_done,
  }

  self.channels:send("shell", msg)
  return msg_id
end

--- Interrupt the running kernel
function KernelManager:interrupt()
  if not self.channels then
    return
  end
  local msg = messages.interrupt_request(self.session)
  self.channels:send("control", msg)
end

--- Shutdown the kernel
---@param restart? boolean
---@param callback? fun()
function KernelManager:shutdown(restart, callback)
  if not self.channels then
    self:_set_status("disconnected")
    if callback then callback() end
    return
  end

  local msg = messages.shutdown_request(self.session, restart)
  self.channels:send("control", msg)

  -- Clean up after a short delay
  vim.defer_fn(function()
    self:_cleanup()
    if restart then
      self:start(function(ok, err)
        if not ok then
          vim.notify("nimbook: restart failed: " .. (err or "unknown"), vim.log.levels.ERROR)
        end
        if callback then callback() end
      end)
    else
      if callback then callback() end
    end
  end, 500)
end

--- Restart the kernel
---@param callback? fun()
function KernelManager:restart(callback)
  self:shutdown(true, callback)
end

--- Connect ZMQ channels to the kernel
function KernelManager:_connect()
  if not self.connection then
    error("no connection info")
  end

  self.ctx = zmq.Context.new()
  self.channels = Channels.new(self.ctx, self.connection, function(channel, msg)
    self:_handle_message(channel, msg)
  end)
end

--- Handle an incoming message from any channel
---@param channel string
---@param msg nimbook.wire.Message
function KernelManager:_handle_message(channel, msg)
  local msg_type = msg.header.msg_type
  local parent_id = msg.parent_header and msg.parent_header.msg_id

  if channel == "iopub" then
    self:_handle_iopub(msg_type, msg, parent_id)
  elseif channel == "shell" then
    self:_handle_shell_reply(msg_type, msg, parent_id)
  elseif channel == "control" then
    -- Control replies (shutdown, interrupt) are informational
    if msg_type == "shutdown_reply" then
      self:_set_status("disconnected")
    end
  end
end

--- Handle IOPub messages (status, output, errors)
---@param msg_type string
---@param msg nimbook.wire.Message
---@param parent_id string|nil
function KernelManager:_handle_iopub(msg_type, msg, parent_id)
  if msg_type == "status" then
    local execution_state = msg.content.execution_state
    if execution_state == "idle" then
      self:_set_status("idle")
      -- Mark this execution's IOPub stream as complete
      if parent_id then
        local cell_state = self._cell_map[parent_id]
        if cell_state then
          cell_state.idle_received = true
          self:_maybe_complete(parent_id)
        end
      end
    elseif execution_state == "busy" then
      self:_set_status("busy")
    end
    return
  end

  -- Output-producing messages
  if msg_type == "stream"
    or msg_type == "execute_result"
    or msg_type == "display_data"
    or msg_type == "error"
  then
    local output = {
      output_type = msg_type,
    }

    if msg_type == "stream" then
      output.name = msg.content.name or "stdout"
      output.text = msg.content.text
      if type(output.text) == "string" then
        output.text = { output.text }
      end
    elseif msg_type == "execute_result" then
      output.data = msg.content.data or {}
      output.metadata = msg.content.metadata or {}
      output.execution_count = msg.content.execution_count
    elseif msg_type == "display_data" then
      output.data = msg.content.data or {}
      output.metadata = msg.content.metadata or {}
    elseif msg_type == "error" then
      output.ename = msg.content.ename or "Error"
      output.evalue = msg.content.evalue or ""
      output.traceback = msg.content.traceback or {}
    end

    -- Track output for the originating execute request
    if parent_id and self._cell_map[parent_id] then
      local cell_state = self._cell_map[parent_id]
      cell_state.outputs[#cell_state.outputs + 1] = output
    end

    -- Notify callback
    if self._on_output and parent_id then
      self._on_output(parent_id, output)
    end
  end
end

--- Handle shell reply messages
---@param msg_type string
---@param msg nimbook.wire.Message
---@param parent_id string|nil
function KernelManager:_handle_shell_reply(msg_type, msg, parent_id)
  if msg_type == "execute_reply" and parent_id then
    local cell_state = self._cell_map[parent_id]
    if cell_state then
      cell_state.execution_count = msg.content and msg.content.execution_count
      cell_state.reply_received = true
      self:_maybe_complete(parent_id)
    end
  elseif msg_type == "kernel_info_reply" then
    local pending = self._pending[parent_id]
    if pending and pending.on_reply then
      pending.on_reply(msg)
    end
  end
end

--- Complete an execution if both shell reply and IOPub idle have been received.
--- This ensures all outputs have arrived before calling on_done.
---@param msg_id string
function KernelManager:_maybe_complete(msg_id)
  local cell_state = self._cell_map[msg_id]
  if not cell_state then
    return
  end
  if cell_state.reply_received and cell_state.idle_received then
    if cell_state.on_done then
      cell_state.on_done(cell_state.outputs, cell_state.execution_count)
    end
    self._cell_map[msg_id] = nil
  end
end

--- Request kernel info (used to verify connection)
---@param callback fun(success: boolean)
function KernelManager:_request_kernel_info(callback)
  if not self.channels then
    callback(false)
    return
  end

  local msg = messages.kernel_info_request(self.session)
  local msg_id = msg.header.msg_id

  -- Set up a timeout
  local responded = false
  self._pending[msg_id] = {
    on_reply = function()
      responded = true
      self._pending[msg_id] = nil
      callback(true)
    end,
  }

  self.channels:send("shell", msg)

  -- Timeout after 10 seconds
  vim.defer_fn(function()
    if not responded then
      self._pending[msg_id] = nil
      callback(false)
    end
  end, 10000)
end

--- Update status and notify
---@param status string
function KernelManager:_set_status(status)
  self.status = status
  if self._on_status then
    self._on_status(status)
  end
end

--- Clean up all resources
function KernelManager:_cleanup()
  if self.channels then
    self.channels:close()
    self.channels = nil
  end
  if self.ctx then
    self.ctx:destroy()
    self.ctx = nil
  end
  if self.process then
    self.process:kill(9) -- SIGKILL
    self.process = nil
  end
  self._pending = {}
  self._cell_map = {}
  self:_set_status("disconnected")
end

--- Find an available TCP port
---@return integer
function KernelManager:_find_port()
  -- Use a random port in the dynamic range
  -- The kernel will bind to these; if they're taken, kernel startup will fail
  -- (which is acceptable -- the user retries)
  return math.random(49152, 65535)
end

return KernelManager
