--- Jupyter kernel channel management
--- Creates and manages ZMQ channels (Shell, IOPub, Control, Stdin, Heartbeat)
--- with Neovim libuv event loop integration via vim.uv.new_poll().
local zmq = require("nimbook.kernel.zmq")
local wire = require("nimbook.kernel.wire")

---@class nimbook.Channels
---@field shell nimbook.zmq.Socket
---@field iopub nimbook.zmq.Socket
---@field control nimbook.zmq.Socket
---@field stdin nimbook.zmq.Socket
---@field heartbeat nimbook.zmq.Socket
---@field _polls table<string, userdata> libuv poll handles
---@field _key string HMAC signing key
---@field _on_message fun(channel: string, msg: nimbook.wire.Message) Message handler
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

  return self
end

--- Send a message on a channel
---@param channel_name "shell"|"control"|"stdin"
---@param msg nimbook.wire.Message
---@return boolean ok
function Channels:send(channel_name, msg)
  local socket = self[channel_name]
  if not socket then
    return false
  end
  local frames = wire.serialize(msg, self._key)
  return socket:send_multipart(frames)
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

  poll:start("r", function(err)
    if err then
      return
    end
    -- ZMQ FD is edge-triggered: when readable, drain all available messages
    self:_drain(name, socket)
  end)
end

--- Drain all available messages from a socket (non-blocking)
---@param name string Channel name
---@param socket nimbook.zmq.Socket
function Channels:_drain(name, socket)
  -- Check ZMQ-level events first
  while socket:has_events() do
    local frames = socket:recv_multipart(zmq.DONTWAIT)
    if frames == nil then
      break
    end
    -- Deserialize and dispatch in Neovim's main thread
    local msg, deserialize_err = wire.deserialize(frames, self._key)
    if msg then
      vim.schedule(function()
        self._on_message(name, msg)
      end)
    elseif deserialize_err then
      vim.schedule(function()
        vim.notify("nimbook: " .. name .. ": " .. deserialize_err, vim.log.levels.DEBUG)
      end)
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
  -- Non-blocking check for pong (caller should retry)
  local data = self.heartbeat:recv(zmq.DONTWAIT)
  return data == "ping"
end

--- Stop all polling and close all sockets
function Channels:close()
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
