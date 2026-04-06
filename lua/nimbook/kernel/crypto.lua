--- HMAC-SHA256 implementation via libcrypto FFI
--- Used to sign Jupyter wire protocol messages.
local ffi = require("ffi")

ffi.cdef([[
  // EVP digest
  typedef struct evp_md_st EVP_MD;
  const EVP_MD *EVP_sha256(void);

  // HMAC
  unsigned char *HMAC(
    const EVP_MD *evp_md,
    const void *key, int key_len,
    const unsigned char *data, size_t data_len,
    unsigned char *md, unsigned int *md_len
  );
]])

local M = {}

-- Load libcrypto - try common names
local crypto_lib
local lib_names = { "crypto", "libcrypto.so.3", "libcrypto.so.1.1", "libcrypto.3.dylib", "libcrypto" }
for _, name in ipairs(lib_names) do
  local ok, lib = pcall(ffi.load, name)
  if ok then
    crypto_lib = lib
    break
  end
end

if not crypto_lib then
  error("nimbook: cannot load libcrypto. It should be installed with OpenSSL.")
end

local sha256 = crypto_lib.EVP_sha256()

--- Compute HMAC-SHA256
---@param key string The signing key
---@param data string The data to sign
---@return string hex Lowercase hex-encoded HMAC
function M.hmac_sha256(key, data)
  local md = ffi.new("unsigned char[32]")
  local md_len = ffi.new("unsigned int[1]")

  local result = crypto_lib.HMAC(sha256, key, #key, data, #data, md, md_len)
  if result == nil then
    error("nimbook: HMAC computation failed")
  end

  -- Convert to hex
  local hex = {}
  for i = 0, md_len[0] - 1 do
    hex[#hex + 1] = string.format("%02x", md[i])
  end
  return table.concat(hex)
end

return M
