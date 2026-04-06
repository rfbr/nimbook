describe("nimbook.util.base64", function()
  local base64 = require("nimbook.util.base64")

  it("encodes and decodes round-trip", function()
    local original = "Hello, World!"
    local encoded = base64.encode(original)
    local decoded = base64.decode(encoded)
    assert.equals(original, decoded)
  end)

  it("encodes known test vector", function()
    assert.equals("SGVsbG8=", base64.encode("Hello"))
    assert.equals("", base64.encode(""))
    assert.equals("YQ==", base64.encode("a"))
    assert.equals("YWI=", base64.encode("ab"))
    assert.equals("YWJj", base64.encode("abc"))
  end)

  it("decodes known test vector", function()
    assert.equals("Hello", base64.decode("SGVsbG8="))
    assert.equals("a", base64.decode("YQ=="))
    assert.equals("ab", base64.decode("YWI="))
    assert.equals("abc", base64.decode("YWJj"))
  end)

  it("handles binary data", function()
    local binary = string.char(0, 1, 2, 255, 254, 253)
    local encoded = base64.encode(binary)
    local decoded = base64.decode(encoded)
    assert.equals(binary, decoded)
  end)

  it("strips whitespace in decode", function()
    local encoded = "SGVs\nbG8="
    assert.equals("Hello", base64.decode(encoded))
  end)
end)

describe("nimbook.util.ansi", function()
  local ansi = require("nimbook.util.ansi")

  it("strips ANSI codes", function()
    local text = "\27[31mError\27[0m: something failed"
    local stripped = ansi.strip(text)
    assert.equals("Error: something failed", stripped)
  end)

  it("parses plain text without ANSI", function()
    local chunks = ansi.parse("hello world")
    assert.equals(1, #chunks)
    assert.equals("hello world", chunks[1][1])
  end)

  it("parses colored text", function()
    local text = "\27[31mred\27[0m normal"
    local chunks = ansi.parse(text)
    assert.is_true(#chunks >= 2)
    assert.equals("red", chunks[1][1])
    assert.equals("NimbookAnsiRed", chunks[1][2])
  end)

  it("handles multiple color changes", function()
    local text = "\27[31mred\27[32mgreen\27[0mplain"
    local chunks = ansi.parse(text)
    assert.equals(3, #chunks)
    assert.equals("red", chunks[1][1])
    assert.equals("NimbookAnsiRed", chunks[1][2])
    assert.equals("green", chunks[2][1])
    assert.equals("NimbookAnsiGreen", chunks[2][2])
    assert.equals("plain", chunks[3][1])
  end)
end)

describe("nimbook.util.html", function()
  local html = require("nimbook.util.html")

  it("converts simple HTML to text", function()
    local text = html.to_text("<p>Hello <b>World</b></p>")
    assert.is_true(text:find("Hello") ~= nil)
    assert.is_true(text:find("World") ~= nil)
  end)

  it("decodes HTML entities", function()
    local text = html.to_text("&amp; &lt; &gt; &quot;")
    assert.equals('& < > "', text)
  end)

  it("converts HTML tables", function()
    local table_html = "<table><tr><th>Name</th><th>Value</th></tr><tr><td>foo</td><td>42</td></tr></table>"
    local text = html.table_to_text(table_html)
    assert.is_true(text:find("Name") ~= nil)
    assert.is_true(text:find("foo") ~= nil)
    assert.is_true(text:find("42") ~= nil)
    -- Should have separator line
    assert.is_true(text:find("%-%-") ~= nil)
  end)

  it("handles heading conversion", function()
    local text = html.to_text("<h1>Title</h1>")
    assert.is_true(text:find("# Title") ~= nil)
  end)
end)

describe("nimbook.graphics", function()
  local gfx = require("nimbook.graphics")

  it("detects a backend without error", function()
    local backend = gfx.detect()
    assert.is_true(backend == "kitty" or backend == "sixel" or backend == "none")
  end)

  it("detects tmux from environment", function()
    -- This depends on whether we're in tmux
    local in_tmux = gfx.in_tmux()
    if vim.env.TMUX then
      assert.is_true(in_tmux)
    else
      assert.is_true(not in_tmux)
    end
  end)

  it("wraps escape sequences for tmux", function()
    local seq = "\027[test"
    local wrapped = gfx.tmux_wrap(seq)
    if vim.env.TMUX then
      assert.is_true(wrapped:find("Ptmux") ~= nil)
    else
      assert.equals(seq, wrapped)
    end
  end)
end)
