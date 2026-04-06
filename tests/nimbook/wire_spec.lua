describe("nimbook.kernel.wire", function()
  -- Wire protocol tests only run if libzmq and libcrypto are available
  local ok_crypto, crypto = pcall(require, "nimbook.kernel.crypto")
  local ok_wire, wire = pcall(require, "nimbook.kernel.wire")

  if not ok_crypto or not ok_wire then
    it("skips wire tests (libzmq/libcrypto not available)", function()
      -- pass
    end)
    return
  end

  describe("crypto", function()
    it("computes HMAC-SHA256", function()
      local hmac = crypto.hmac_sha256("key", "data")
      assert.is_not_nil(hmac)
      assert.equals(64, #hmac) -- 32 bytes = 64 hex chars
      -- Known test vector: HMAC-SHA256("key", "data")
      -- Expected: 5031fe3d989c6d1537a013fa6e739da23463fdaec3b70137d828e36ace221bd0
      assert.equals("5031fe3d989c6d1537a013fa6e739da23463fdaec3b70137d828e36ace221bd0", hmac)
    end)
  end)

  describe("wire protocol", function()
    it("creates message headers", function()
      local header = wire.make_header("execute_request", "test-session")
      assert.equals("execute_request", header.msg_type)
      assert.equals("test-session", header.session)
      assert.equals("nimbook", header.username)
      assert.equals("5.3", header.version)
      assert.is_not_nil(header.msg_id)
      assert.is_not_nil(header.date)
    end)

    it("serializes and deserializes messages", function()
      local msg = {
        identities = { "ident1" },
        header = wire.make_header("execute_request", "sess1"),
        parent_header = {},
        metadata = {},
        content = { code = "print('hello')", silent = false },
        buffers = {},
      }

      local key = "test-key-123"
      local frames = wire.serialize(msg, key)
      assert.is_not_nil(frames)
      assert.is_true(#frames >= 6) -- ident + delimiter + sig + 4 json parts

      local deserialized, err = wire.deserialize(frames, key)
      assert.is_nil(err)
      assert.is_not_nil(deserialized)
      assert.equals("execute_request", deserialized.header.msg_type)
      assert.equals("print('hello')", deserialized.content.code)
      assert.equals(1, #deserialized.identities)
      assert.equals("ident1", deserialized.identities[1])
    end)

    it("rejects messages with bad signature", function()
      local msg = {
        identities = {},
        header = wire.make_header("execute_request", "sess1"),
        parent_header = {},
        metadata = {},
        content = { code = "x = 1" },
        buffers = {},
      }

      local frames = wire.serialize(msg, "correct-key")
      local result, err = wire.deserialize(frames, "wrong-key")
      assert.is_nil(result)
      assert.is_true(err:find("signature") ~= nil)
    end)

    it("allows empty key (no auth)", function()
      local msg = {
        identities = {},
        header = wire.make_header("test", "sess"),
        parent_header = {},
        metadata = {},
        content = {},
        buffers = {},
      }

      local frames = wire.serialize(msg, "")
      local result, err = wire.deserialize(frames, "")
      assert.is_nil(err)
      assert.is_not_nil(result)
    end)
  end)
end)

describe("nimbook.kernel.messages", function()
  local ok_msg, messages = pcall(require, "nimbook.kernel.messages")
  if not ok_msg then
    it("skips message tests (dependencies not available)", function() end)
    return
  end

  it("creates execute_request", function()
    local msg = messages.execute_request("sess1", "print('hi')")
    assert.equals("execute_request", msg.header.msg_type)
    assert.equals("print('hi')", msg.content.code)
    assert.equals(false, msg.content.silent)
  end)

  it("creates kernel_info_request", function()
    local msg = messages.kernel_info_request("sess1")
    assert.equals("kernel_info_request", msg.header.msg_type)
  end)

  it("creates interrupt_request", function()
    local msg = messages.interrupt_request("sess1")
    assert.equals("interrupt_request", msg.header.msg_type)
  end)

  it("creates shutdown_request", function()
    local msg = messages.shutdown_request("sess1", true)
    assert.equals("shutdown_request", msg.header.msg_type)
    assert.equals(true, msg.content.restart)
  end)
end)
