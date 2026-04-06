--- Jupyter kernel channel management
--- Creates and manages ZMQ channels (Shell, IOPub, Control, Stdin, Heartbeat)
--- with Neovim libuv event loop integration.
local zmq = require("nimbook.kernel.zmq")
local wire = require("nimbook.kernel.wire")

---@class nimbook.Channels
---@field shell nimbook.zmq.Socket
---@field iopub nimbook.zmq.Socket
---@field control nimbook.zmq.Socket
---@field stdin nimbook.zmq.Socket
---@field heartbeat nimbook.zmq.Socket
---@field _polls table<string, userdata> libuv poll handles
---@field _timer userdata|nil Fallback poll timer
---@field _key string HMAC signing key
---@field _on_message fun(channel: string, msg: nimbook.wire.Message) Message handler
---@field _closed boolean Whether channels have been closed
local Channels = {}
Channels.__index = Channels

--- Create and connect all channels to a running kernel
---@param ctx nimbook.zmq.Context ZMQ context
---@param connection table Parsed connection file
---@param on_message fun(channel: string, msg: nimbook.wire.Message)
---@return nimbook.Channels
function Channels.new(ctx, connection, on_message)
  local self = setmetatable({}, Channels)
  self._key = connection.key or ""
  self._on_message = on_message
  self._polls = {}
  self._timer = nil
  self._closed = false

  local transport = connection.transport or "tcp"
  local ip = connection.ip or "127.0.0.1"

  local function endpoint(port)
    return string.format("%s://%s:%d", transport, ip, port)
  end

  -- Create sockets
  self.shell = ctx:socket(zmq.DEALER)
  self.iopub = ctx:socket(zmq.SUB)
  self.control = ctx:socket(zmq.DEALER)
  self.stdin = ctx:socket(zmq.DEALER)
  self.heartbeat = ctx:socket(zmq.REQ)

  -- Set identities for DEALER sockets
  local identity = "nimbook-" .. tostring(vim.uv.hrtime())
  self.shell:set_identity(identity)
  self.control:set_identity(identity)
  self.stdin:set_identity(identity)

  -- Subscribe IOPub to all messages
  self.iopub:subscribe("")

  -- Connect to kernel ports
  self.shell:connect(endpoint(connection.shell_port))
  self.iopub:connect(endpoint(connection.iopub_port))
  self.control:connect(endpoint(connection.control_port))
  self.stdin:connect(endpoint(connection.stdin_port))
  self.heartbeat:connect(endpoint(connection.hb_port))

  -- Start polling on channels that receive messages
  self:_start_poll("shell", self.shell)
  self:_start_poll("iopub", self.iopub)
  self:_start_poll("control", self.control)

  -- Fallback timer: ZMQ FD signaling can miss wakeups when combined with
  -- libuv polling. A 50ms Neovim timer catches any stranded messages.
  -- Uses vim.schedule_wrap so the callback runs in a safe Neovim context.
  self._timer = vim.uv.new_timer()
  self._timer:start(50, 50, vim.schedule_wrap(function()
    if self._closed then
      return
    end
    self:_drain_all()
  end))

  return self
end

--- Send a message on a channel
---@param channel_name "shell"|"control"|"stdin"
---@param msg nimbook.wire.Message
---@return boolean ok
function Channels:send(channel_name, msg)
  local socket = self[channel_name]
  if not socket then
    vim.notify("nimbook: unknown channel " .. channel_name, vim.log.levels.ERROR)
    return false
  end
  local frames = wire.serialize(msg, self._key)
  local ok = socket:send_multipart(frames)
  if not ok then
    vim.notify("nimbook: failed to send on " .. channel_name .. ": " .. zmq.last_error(), vim.log.levels.ERROR)
  end
  return ok
end

--- Start polling a ZMQ socket's FD with libuv
---@param name string Channel name
---@param socket nimbook.zmq.Socket
function Channels:_start_poll(name, socket)
  local fd = socket:get_fd()
  local poll = vim.uv.new_poll(fd)
  if not poll then
    vim.notify("nimbook: failed to create poll for " .. name, vim.log.levels.WARN)
    return
  end

  self._polls[name] = poll

  poll:start("r", vim.schedule_wrap(function()
    if self._closed then
      return
    end
    self:_drain_all()
  end))
end

--- Drain all channels. Called from both poll callbacks and the fallback timer.
function Channels:_drain_all()
  self:_drain("shell", self.shell)
  self:_drain("iopub", self.iopub)
  self:_drain("control", self.control)
end

--- Drain all available messages from a socket (non-blocking)
---@param name string Channel name
---@param socket nimbook.zmq.Socket
function Channels:_drain(name, socket)
  if self._closed or not socket._ptr then
    return
  end
  for _ = 1, 1000 do -- safety cap to prevent infinite loops
    local ok, frames = pcall(socket.recv_multipart, socket, zmq.DONTWAIT)
    if not ok or frames == nil then
      break
    end
    -- Deserialize and dispatch
    local msg, err = wire.deserialize(frames, self._key)
    if msg then
      -- Dispatch directly (we're already in vim.schedule context)
      local dispatch_ok, dispatch_err = pcall(self._on_message, name, msg)
      if not dispatch_ok then
        vim.notify("nimbook: dispatch error on " .. name .. ": " .. tostring(dispatch_err), vim.log.levels.ERROR)
      end
    else
      vim.notify(
        "nimbook: " .. name .. " deserialize error: " .. (err or "unknown") .. " (" .. #frames .. " frames)",
        vim.log.levels.WARN
      )
    end
  end
end

--- Send a heartbeat ping and check response
---@return boolean alive
function Channels:ping()
  local ok = self.heartbeat:send("ping", 0)
  if not ok then
    return false
  end
  local data = self.heartbeat:recv(zmq.DONTWAIT)
  return data == "ping"
end

--- Stop all polling and close all sockets
function Channels:close()
  self._closed = true
  if self._timer then
    self._timer:stop()
    self._timer:close()
    self._timer = nil
  end
  for name, poll in pairs(self._polls) do
    poll:stop()
    poll:close()
    self._polls[name] = nil
  end
  self.shell:close()
  self.iopub:close()
  self.control:close()
  self.stdin:close()
  self.heartbeat:close()
end

return Channels
