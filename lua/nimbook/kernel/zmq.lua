--- LuaJIT FFI bindings to libzmq
--- Provides Context and Socket abstractions for Jupyter kernel communication.
local ffi = require("ffi")

ffi.cdef([[
  // ZMQ context
  void *zmq_ctx_new(void);
  int zmq_ctx_term(void *context);

  // ZMQ socket
  void *zmq_socket(void *context, int type);
  int zmq_close(void *socket);
  int zmq_connect(void *socket, const char *endpoint);
  int zmq_bind(void *socket, const char *endpoint);
  int zmq_setsockopt(void *socket, int option_name, const void *option_value, size_t option_len);
  int zmq_getsockopt(void *socket, int option_name, void *option_value, size_t *option_len);

  // ZMQ message
  typedef struct { unsigned char _[64]; } zmq_msg_t;
  int zmq_msg_init(zmq_msg_t *msg);
  int zmq_msg_init_size(zmq_msg_t *msg, size_t size);
  int zmq_msg_close(zmq_msg_t *msg);
  void *zmq_msg_data(zmq_msg_t *msg);
  size_t zmq_msg_size(zmq_msg_t *msg);
  int zmq_msg_more(zmq_msg_t *msg);
  int zmq_msg_send(zmq_msg_t *msg, void *socket, int flags);
  int zmq_msg_recv(zmq_msg_t *msg, void *socket, int flags);

  // ZMQ poll (for getting FD)
  int zmq_errno(void);
  const char *zmq_strerror(int errnum);
]])

local M = {}

-- Load libzmq - try common names
local zmq_lib
local lib_names = { "zmq", "libzmq.so.5", "libzmq.5.dylib", "libzmq" }
for _, name in ipairs(lib_names) do
  local ok, lib = pcall(ffi.load, name)
  if ok then
    zmq_lib = lib
    break
  end
end

if not zmq_lib then
  error("nimbook: cannot load libzmq. Install it: apt install libzmq5 / brew install zmq")
end

-- ZMQ constants
M.PAIR = 0
M.PUB = 1
M.SUB = 2
M.REQ = 3
M.REP = 4
M.DEALER = 5
M.ROUTER = 6
M.PULL = 7
M.PUSH = 8

M.DONTWAIT = 1
M.SNDMORE = 2

M.SUBSCRIBE = 6
M.IDENTITY = 5
M.FD = 14
M.EVENTS = 15
M.LINGER = 17

M.POLLIN = 1

M.EAGAIN = 11

--- Get the last ZMQ error as a string
---@return string
function M.last_error()
  local errno = zmq_lib.zmq_errno()
  return ffi.string(zmq_lib.zmq_strerror(errno))
end

--- Get the last ZMQ errno
---@return integer
function M.last_errno()
  return zmq_lib.zmq_errno()
end

--
-- Context
--

---@class nimbook.zmq.Context
---@field _ptr ffi.cdata*
local Context = {}
Context.__index = Context
M.Context = Context

---@return nimbook.zmq.Context
function Context.new()
  local ptr = zmq_lib.zmq_ctx_new()
  if ptr == nil then
    error("nimbook: zmq_ctx_new failed: " .. M.last_error())
  end
  local self = setmetatable({ _ptr = ptr }, Context)
  return self
end

function Context:destroy()
  if self._ptr ~= nil then
    zmq_lib.zmq_ctx_term(self._ptr)
    self._ptr = nil
  end
end

---@param socket_type integer ZMQ socket type constant
---@return nimbook.zmq.Socket
function Context:socket(socket_type)
  return M.Socket.new(self._ptr, socket_type)
end

--
-- Socket
--

---@class nimbook.zmq.Socket
---@field _ptr ffi.cdata*
local Socket = {}
Socket.__index = Socket
M.Socket = Socket

---@param ctx_ptr ffi.cdata*
---@param socket_type integer
---@return nimbook.zmq.Socket
function Socket.new(ctx_ptr, socket_type)
  local ptr = zmq_lib.zmq_socket(ctx_ptr, socket_type)
  if ptr == nil then
    error("nimbook: zmq_socket failed: " .. M.last_error())
  end
  local self = setmetatable({ _ptr = ptr }, Socket)
  -- Set linger to 0 so close doesn't block
  self:set_option_int(M.LINGER, 0)
  return self
end

function Socket:close()
  if self._ptr ~= nil then
    zmq_lib.zmq_close(self._ptr)
    self._ptr = nil
  end
end

---@param endpoint string
function Socket:connect(endpoint)
  local rc = zmq_lib.zmq_connect(self._ptr, endpoint)
  if rc ~= 0 then
    error("nimbook: zmq_connect failed: " .. M.last_error())
  end
end

---@param endpoint string
function Socket:bind(endpoint)
  local rc = zmq_lib.zmq_bind(self._ptr, endpoint)
  if rc ~= 0 then
    error("nimbook: zmq_bind failed: " .. M.last_error())
  end
end

--- Set an integer socket option
---@param option integer
---@param value integer
function Socket:set_option_int(option, value)
  local val = ffi.new("int[1]", value)
  local rc = zmq_lib.zmq_setsockopt(self._ptr, option, val, ffi.sizeof("int"))
  if rc ~= 0 then
    error("nimbook: zmq_setsockopt failed: " .. M.last_error())
  end
end

--- Set a string socket option
---@param option integer
---@param value string
function Socket:set_option_string(option, value)
  local rc = zmq_lib.zmq_setsockopt(self._ptr, option, value, #value)
  if rc ~= 0 then
    error("nimbook: zmq_setsockopt failed: " .. M.last_error())
  end
end

--- Get the socket's file descriptor for use with libuv polling
---@return integer fd
function Socket:get_fd()
  local fd = ffi.new("int[1]")
  local len = ffi.new("size_t[1]", ffi.sizeof("int"))
  local rc = zmq_lib.zmq_getsockopt(self._ptr, M.FD, fd, len)
  if rc ~= 0 then
    error("nimbook: zmq_getsockopt(FD) failed: " .. M.last_error())
  end
  return fd[0]
end

--- Check if socket has events ready
---@return boolean has_input
function Socket:has_events()
  local events = ffi.new("int[1]")
  local len = ffi.new("size_t[1]", ffi.sizeof("int"))
  local rc = zmq_lib.zmq_getsockopt(self._ptr, M.EVENTS, events, len)
  if rc ~= 0 then
    return false
  end
  return bit.band(events[0], M.POLLIN) ~= 0
end

--- Subscribe to messages (SUB sockets only)
---@param filter string Filter prefix ("" for all)
function Socket:subscribe(filter)
  self:set_option_string(M.SUBSCRIBE, filter)
end

--- Set socket identity
---@param identity string
function Socket:set_identity(identity)
  self:set_option_string(M.IDENTITY, identity)
end

--- Send a single frame
---@param data string
---@param flags? integer ZMQ flags (e.g., SNDMORE, DONTWAIT)
---@return boolean ok
function Socket:send(data, flags)
  local msg = ffi.new("zmq_msg_t")
  zmq_lib.zmq_msg_init_size(msg, #data)
  ffi.copy(zmq_lib.zmq_msg_data(msg), data, #data)
  local rc = zmq_lib.zmq_msg_send(msg, self._ptr, flags or 0)
  if rc == -1 then
    zmq_lib.zmq_msg_close(msg)
    return false
  end
  return true
end

--- Send a multipart message
---@param frames string[] Array of frame data
---@return boolean ok
function Socket:send_multipart(frames)
  for i, frame in ipairs(frames) do
    local flags = (i < #frames) and M.SNDMORE or 0
    if not self:send(frame, flags) then
      return false
    end
  end
  return true
end

--- Receive a single frame (non-blocking)
---@return string|nil data, boolean|nil has_more
function Socket:recv(flags)
  local msg = ffi.new("zmq_msg_t")
  zmq_lib.zmq_msg_init(msg)
  local rc = zmq_lib.zmq_msg_recv(msg, self._ptr, flags or 0)
  if rc == -1 then
    zmq_lib.zmq_msg_close(msg)
    return nil, nil
  end
  local data = ffi.string(zmq_lib.zmq_msg_data(msg), zmq_lib.zmq_msg_size(msg))
  local more = zmq_lib.zmq_msg_more(msg) == 1
  zmq_lib.zmq_msg_close(msg)
  return data, more
end

--- Receive a complete multipart message (non-blocking)
---@return string[]|nil frames
function Socket:recv_multipart(flags)
  flags = flags or M.DONTWAIT
  local frames = {}
  local data, more = self:recv(flags)
  if data == nil then
    return nil
  end
  frames[#frames + 1] = data
  while more do
    data, more = self:recv(flags)
    if data == nil then
      break
    end
    frames[#frames + 1] = data
  end
  return frames
end

return M
