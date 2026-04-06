describe("nimbook.export", function()
  local Notebook = require("nimbook.notebook")
  local export = require("nimbook.export")

  local fixture_path = "tests/fixtures/simple.ipynb"

  local function load_notebook()
    local f = io.open(fixture_path, "r")
    local content = f:read("*a")
    f:close()
    return Notebook.parse(content, fixture_path)
  end

  describe("to_python", function()
    it("exports cells with percent markers", function()
      local notebook = load_notebook()
      local py = export.to_python(notebook)

      -- Should have percent markers
      assert.is_true(py:find("%# %%%%") ~= nil)

      -- Should have markdown marker
      assert.is_true(py:find("%[markdown%]") ~= nil)

      -- Should contain code source
      assert.is_true(py:find("import pandas") ~= nil)

      -- Markdown should be commented
      assert.is_true(py:find("# # Data Analysis") ~= nil)
    end)

    it("includes kernel metadata header", function()
      local notebook = load_notebook()
      local py = export.to_python(notebook)

      assert.is_true(py:find("kernelspec") ~= nil)
      assert.is_true(py:find("python3") ~= nil)
    end)
  end)

  describe("to_markdown", function()
    it("exports code cells as fenced blocks", function()
      local notebook = load_notebook()
      local md = export.to_markdown(notebook)

      assert.is_true(md:find("```python") ~= nil)
      assert.is_true(md:find("import pandas") ~= nil)
    end)

    it("exports markdown cells as plain text", function()
      local notebook = load_notebook()
      local md = export.to_markdown(notebook)

      assert.is_true(md:find("# Data Analysis") ~= nil)
    end)

    it("includes outputs in details block", function()
      local notebook = load_notebook()
      local md = export.to_markdown(notebook)

      -- Cell 2 has stream output
      assert.is_true(md:find("<details>") ~= nil)
      assert.is_true(md:find("Output") ~= nil)
    end)
  end)
end)

describe("nimbook.fold", function()
  local fold = require("nimbook.fold")

  it("module loads without error", function()
    assert.is_not_nil(fold.foldexpr)
    assert.is_not_nil(fold.foldtext)
  end)
end)

describe("nimbook.completion", function()
  local ok, completion = pcall(require, "nimbook.completion")

  it("module loads without error", function()
    assert.is_true(ok)
    assert.is_not_nil(completion)
  end)

  it("creates a source instance", function()
    local src = completion.new()
    assert.is_not_nil(src)
    assert.equals("nimbook", src:get_debug_name())
  end)
end)
