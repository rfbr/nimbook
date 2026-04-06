--- Jupyter wire protocol implementation
--- Handles message framing, serialization, and HMAC signing.
---
--- Wire format (multipart ZMQ message):
---   [identity_frames..., '<IDS|MSG>', hmac_signature, header, parent_header, metadata, content, buffers...]
local crypto = require("nimbook.kernel.crypto")
local util = require("nimbook.util")

local M = {}

local DELIMITER = "<IDS|MSG>"

---@class nimbook.wire.Message
---@field identities string[] Identity frames
---@field header table Message header
---@field parent_header table Parent message header
---@field metadata table Message metadata
---@field content table Message content
---@field buffers string[] Binary buffers

--- Create a new message header
---@param msg_type string Jupyter message type
---@param session string Session ID
---@param username? string
---@return table header
function M.make_header(msg_type, session, username)
  return {
    msg_id = util.uuid(),
    msg_type = msg_type,
    session = session,
    username = username or "nimbook",
    date = os.date("!%Y-%m-%dT%H:%M:%S.000000Z"),
    version = "5.3",
  }
end

--- Sign the message parts with HMAC-SHA256
---@param key string Signing key
---@param header_str string JSON-encoded header
---@param parent_str string JSON-encoded parent header
---@param metadata_str string JSON-encoded metadata
---@param content_str string JSON-encoded content
---@return string signature Hex-encoded HMAC
function M.sign(key, header_str, parent_str, metadata_str, content_str)
  if key == "" then
    return ""
  end
  local data = header_str .. parent_str .. metadata_str .. content_str
  return crypto.hmac_sha256(key, data)
end

--- Serialize a message into ZMQ multipart frames
---@param msg nimbook.wire.Message
---@param key string Signing key
---@return string[] frames
--- Encode a table as a JSON object, ensuring empty tables become {} not []
---@param tbl table
---@return string
local function encode_dict(tbl)
  if tbl == nil or (type(tbl) == "table" and next(tbl) == nil) then
    return "{}"
  end
  return vim.json.encode(tbl)
end

function M.serialize(msg, key)
  local header_str = encode_dict(msg.header)
  local parent_str = encode_dict(msg.parent_header)
  local metadata_str = encode_dict(msg.metadata)
  local content_str = encode_dict(msg.content)

  local signature = M.sign(key, header_str, parent_str, metadata_str, content_str)

  local frames = {}
  -- Identity frames
  for _, id in ipairs(msg.identities or {}) do
    frames[#frames + 1] = id
  end
  -- Delimiter
  frames[#frames + 1] = DELIMITER
  -- Signature
  frames[#frames + 1] = signature
  -- Message parts
  frames[#frames + 1] = header_str
  frames[#frames + 1] = parent_str
  frames[#frames + 1] = metadata_str
  frames[#frames + 1] = content_str
  -- Buffers
  for _, buf in ipairs(msg.buffers or {}) do
    frames[#frames + 1] = buf
  end

  return frames
end

--- Deserialize ZMQ multipart frames into a message
---@param frames string[]
---@param key string Signing key (empty string to skip verification)
---@return nimbook.wire.Message|nil msg
---@return string|nil error
function M.deserialize(frames, key)
  -- Find the delimiter
  local delim_idx = nil
  for i, frame in ipairs(frames) do
    if frame == DELIMITER then
      delim_idx = i
      break
    end
  end

  if not delim_idx then
    return nil, "no delimiter found in message"
  end

  -- Need at least: delimiter + signature + header + parent + metadata + content
  if #frames < delim_idx + 5 then
    return nil, "incomplete message: not enough frames after delimiter"
  end

  -- Extract identities (everything before delimiter)
  local identities = {}
  for i = 1, delim_idx - 1 do
    identities[#identities + 1] = frames[i]
  end

  local signature = frames[delim_idx + 1]
  local header_str = frames[delim_idx + 2]
  local parent_str = frames[delim_idx + 3]
  local metadata_str = frames[delim_idx + 4]
  local content_str = frames[delim_idx + 5]

  -- Verify signature
  if key ~= "" then
    local expected = M.sign(key, header_str, parent_str, metadata_str, content_str)
    if signature ~= expected then
      return nil, "HMAC signature mismatch"
    end
  end

  -- Parse JSON
  local ok_h, header = pcall(vim.json.decode, header_str)
  if not ok_h then
    return nil, "failed to decode header: " .. tostring(header)
  end

  local ok_p, parent_header = pcall(vim.json.decode, parent_str)
  if not ok_p then
    parent_header = {}
  end

  local ok_m, metadata = pcall(vim.json.decode, metadata_str)
  if not ok_m then
    metadata = {}
  end

  local ok_c, content = pcall(vim.json.decode, content_str)
  if not ok_c then
    content = {}
  end

  -- Collect buffers
  local buffers = {}
  for i = delim_idx + 6, #frames do
    buffers[#buffers + 1] = frames[i]
  end

  return {
    identities = identities,
    header = header,
    parent_header = parent_header,
    metadata = metadata,
    content = content,
    buffers = buffers,
  }
end

return M
