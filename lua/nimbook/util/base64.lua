--- Base64 encoding and decoding
--- Used for image data in .ipynb outputs and Kitty graphics protocol.
local ffi = require("ffi")

local M = {}

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Build decode lookup table
local b64decode_lut = {}
for i = 1, #b64chars do
  b64decode_lut[b64chars:byte(i)] = i - 1
end

--- Decode a base64-encoded string to raw bytes
---@param input string Base64-encoded string (may contain whitespace/newlines)
---@return string decoded Raw bytes
function M.decode(input)
  -- Strip whitespace
  input = input:gsub("%s", "")

  local len = #input
  -- Calculate output size (accounting for padding)
  local pad = 0
  if input:sub(-1) == "=" then
    pad = 1
  end
  if input:sub(-2, -2) == "=" then
    pad = 2
  end
  local out_len = math.floor(len / 4) * 3 - pad

  local buf = ffi.new("uint8_t[?]", out_len)
  local j = 0

  for i = 1, len, 4 do
    local a = b64decode_lut[input:byte(i)] or 0
    local b = b64decode_lut[input:byte(i + 1)] or 0
    local c = b64decode_lut[input:byte(i + 2)] or 0
    local d = b64decode_lut[input:byte(i + 3)] or 0

    local n = a * 262144 + b * 4096 + c * 64 + d

    if j < out_len then
      buf[j] = math.floor(n / 65536) % 256
      j = j + 1
    end
    if j < out_len then
      buf[j] = math.floor(n / 256) % 256
      j = j + 1
    end
    if j < out_len then
      buf[j] = n % 256
      j = j + 1
    end
  end

  return ffi.string(buf, out_len)
end

--- Encode raw bytes to base64
---@param input string Raw bytes
---@return string encoded Base64 string
function M.encode(input)
  local len = #input
  local out = {}

  for i = 1, len, 3 do
    local a = input:byte(i)
    local b = (i + 1 <= len) and input:byte(i + 1) or 0
    local c = (i + 2 <= len) and input:byte(i + 2) or 0

    local n = a * 65536 + b * 256 + c

    out[#out + 1] = b64chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
    out[#out + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)

    if i + 1 <= len then
      out[#out + 1] = b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
    else
      out[#out + 1] = "="
    end

    if i + 2 <= len then
      out[#out + 1] = b64chars:sub(n % 64 + 1, n % 64 + 1)
    else
      out[#out + 1] = "="
    end
  end

  return table.concat(out)
end

return M
