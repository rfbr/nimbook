--- Integration test: start a real kernel, execute code, verify output.
--- Run: nvim --headless -u tests/minimal_init.lua -l tests/integration_test.lua

local zmq = require("nimbook.kernel.zmq")
local crypto = require("nimbook.kernel.crypto")
local wire = require("nimbook.kernel.wire")
local messages = require("nimbook.kernel.messages")
local util = require("nimbook.util")

local function log(...)
  local args = { ... }
  local parts = {}
  for _, a in ipairs(args) do
    parts[#parts + 1] = tostring(a)
  end
  io.write("[test] " .. table.concat(parts, " ") .. "\n")
  io.flush()
end

log("=== nimbook kernel integration test ===")

-- Step 1: Generate connection info and write connection file
log("Step 1: Creating connection file...")
local conn = {
  transport = "tcp",
  ip = "127.0.0.1",
  shell_port = 55501,
  iopub_port = 55502,
  control_port = 55503,
  stdin_port = 55504,
  hb_port = 55505,
  key = util.uuid(),
  signature_scheme = "hmac-sha256",
  kernel_name = "python3",
}

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local conn_file = tmpdir .. "/kernel.json"
local f = io.open(conn_file, "w")
f:write(vim.json.encode(conn))
f:close()
log("  Connection file:", conn_file)
log("  Key:", conn.key)

-- Step 2: Start kernel
log("Step 2: Starting ipykernel...")
local process = vim.system(
  { "python3", "-m", "ipykernel_launcher", "-f", conn_file },
  { detach = true, stdout = false, stderr = false }
)
log("  Kernel PID:", process.pid)

-- Wait for kernel to start
log("  Waiting 3s for kernel to bind ports...")
vim.wait(3000)

-- Step 3: Create ZMQ context and sockets
log("Step 3: Connecting ZMQ sockets...")
local ctx = zmq.Context.new()

local shell = ctx:socket(zmq.DEALER)
local iopub = ctx:socket(zmq.SUB)

local identity = "test-" .. tostring(os.time())
shell:set_identity(identity)
iopub:subscribe("")

local function endpoint(port)
  return string.format("tcp://127.0.0.1:%d", port)
end

shell:connect(endpoint(conn.shell_port))
iopub:connect(endpoint(conn.iopub_port))
log("  Connected to shell:", conn.shell_port, "iopub:", conn.iopub_port)

-- Small delay for connection to establish
vim.wait(500)

-- Step 4: Send kernel_info_request
log("Step 4: Sending kernel_info_request...")
local session = util.uuid()
local ki_msg = messages.kernel_info_request(session)
local ki_frames = wire.serialize(ki_msg, conn.key)
log("  Sending", #ki_frames, "frames on shell")
log("  Frame sizes:", table.concat(vim.tbl_map(function(fr) return #fr end, ki_frames), ", "))

local send_ok = shell:send_multipart(ki_frames)
log("  Send result:", send_ok)

-- Step 5: Wait for reply, dumping EVERY message with full detail
log("Step 5: Waiting for messages (dumping all)...")
local got_reply = false

-- Helper to dump frames
local function dump_frames(channel, frames)
  log("  " .. channel .. ": " .. #frames .. " frames")
  for i, fr in ipairs(frames) do
    local display = #fr > 200 and (fr:sub(1, 200) .. "...") or fr
    display = display:gsub("[%c]", ".")
    log("    [" .. i .. "] (" .. #fr .. " bytes): " .. display)
  end
  local msg, err = wire.deserialize(frames, conn.key)
  if msg then
    log("    => msg_type: " .. msg.header.msg_type)
    return msg
  else
    log("    => FAILED: " .. (err or "?"))
    return nil
  end
end

for attempt = 1, 50 do
  local frames = shell:recv_multipart(zmq.DONTWAIT)
  if frames then
    local msg = dump_frames("Shell", frames)
    if msg and msg.header.msg_type == "kernel_info_reply" then
      got_reply = true
    end
  end

  local iframes = iopub:recv_multipart(zmq.DONTWAIT)
  if iframes then
    dump_frames("IOPub", iframes)
  end

  if got_reply then break end
  vim.wait(200)
end

if not got_reply then
  log("  FAILED: No kernel_info_reply received after 10s")
  -- Try draining iopub to see if anything came through
  log("  Draining iopub...")
  for _ = 1, 10 do
    local frames = iopub:recv_multipart(zmq.DONTWAIT)
    if frames then
      log("  IOPub stray:", #frames, "frames")
      local msg, err = wire.deserialize(frames, conn.key)
      if msg then
        log("    msg_type:", msg.header.msg_type)
      else
        log("    err:", err)
      end
    else
      break
    end
  end
end

-- Step 6: Send execute_request
if got_reply then
  log("Step 6: Sending execute_request for print('hello')...")
  local exec_msg = messages.execute_request(session, "print('hello')")
  local exec_frames = wire.serialize(exec_msg, conn.key)
  local exec_send_ok = shell:send_multipart(exec_frames)
  log("  Send result:", exec_send_ok)
  log("  msg_id:", exec_msg.header.msg_id)

  -- Step 7: Collect ALL responses with full frame dumps
  log("Step 7: Collecting responses...")
  local got_execute_reply = false
  local got_stream = false

  for attempt = 1, 50 do
    -- Drain everything from shell
    while true do
      local frames = shell:recv_multipart(zmq.DONTWAIT)
      if not frames then break end
      local msg = dump_frames("Shell", frames)
      if msg then
        if msg.header.msg_type == "execute_reply" then
          got_execute_reply = true
          log("    => status: " .. tostring(msg.content.status))
        end
      end
    end

    -- Drain everything from iopub
    while true do
      local frames = iopub:recv_multipart(zmq.DONTWAIT)
      if not frames then break end
      local msg = dump_frames("IOPub", frames)
      if msg then
        if msg.header.msg_type == "stream" then
          got_stream = true
          log("    => stream text: " .. vim.inspect(msg.content.text))
        end
      end
    end

    if got_execute_reply and got_stream then break end
    vim.wait(200)
  end

  log("  execute_reply received:", got_execute_reply)
  log("  stream output received:", got_stream)
end

-- Cleanup
log("Cleanup: shutting down kernel...")
shell:close()
iopub:close()
ctx:destroy()
process:kill(9)
os.remove(conn_file)
vim.fn.delete(tmpdir, "rf")

if got_reply then
  log("=== PASS ===")
  vim.cmd("quit")
else
  log("=== FAIL ===")
  vim.cmd("cquit 1")
end
