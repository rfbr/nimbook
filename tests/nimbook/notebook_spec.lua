local Notebook = require("nimbook.notebook")
local Cell = require("nimbook.notebook.cell")
local buf_mod = require("nimbook.render.buffer")

describe("nimbook.notebook", function()
  local fixture_path = "tests/fixtures/simple.ipynb"

  describe("parse", function()
    it("parses a valid .ipynb file", function()
      local f = io.open(fixture_path, "r")
      assert.is_not_nil(f)
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      assert.is_not_nil(notebook)
      assert.equals(3, #notebook.cells)
      assert.equals("markdown", notebook.cells[1].cell_type)
      assert.equals("code", notebook.cells[2].cell_type)
      assert.equals("code", notebook.cells[3].cell_type)
    end)

    it("preserves cell IDs", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      assert.equals("abc123", notebook.cells[1].id)
      assert.equals("def456", notebook.cells[2].id)
      assert.equals("ghi789", notebook.cells[3].id)
    end)

    it("reads cell sources correctly", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      local src = notebook.cells[1]:get_source()
      assert.is_true(src:find("Data Analysis") ~= nil)
    end)

    it("reads outputs correctly", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      local outputs = notebook.cells[2]:get_outputs()
      assert.equals(1, #outputs)
      assert.equals("stream", outputs[1].output_type)
    end)

    it("gets execution count", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      assert.equals(1, notebook.cells[2]:get_execution_count())
      assert.is_nil(notebook.cells[3]:get_execution_count())
    end)

    it("detects the language", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      assert.equals("python", notebook:get_language())
    end)
  end)

  describe("cell operations", function()
    it("creates new code cells", function()
      local cell = Cell.new_code()
      assert.equals("code", cell.cell_type)
      assert.equals("", cell:get_source())
      assert.same({}, cell:get_outputs())
    end)

    it("creates new markdown cells", function()
      local cell = Cell.new_markdown()
      assert.equals("markdown", cell.cell_type)
      assert.equals("", cell:get_source())
    end)

    it("set_source splits into lines correctly", function()
      local cell = Cell.new_code()
      cell:set_source("line1\nline2\nline3")
      assert.same({ "line1\n", "line2\n", "line3" }, cell.raw.source)
    end)

    it("set_source handles trailing newline", function()
      local cell = Cell.new_code()
      cell:set_source("line1\nline2\n")
      assert.same({ "line1\n", "line2\n" }, cell.raw.source)
    end)

    it("get_display_lines strips trailing newline", function()
      local cell = Cell.new_code()
      cell:set_source("line1\nline2\n")
      assert.same({ "line1", "line2" }, cell:get_display_lines())
    end)
  end)

  describe("notebook_to_lines", function()
    it("generates correct buffer lines", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      local lines = buf_mod.notebook_to_lines(notebook)

      -- First cell is markdown, should be plain text
      assert.equals("# Data Analysis", lines[1])
      assert.equals("Load and explore the dataset.", lines[2])

      -- Separator
      assert.equals("", lines[3])

      -- Second cell is code, should have fences
      assert.equals("```python", lines[4])
      assert.equals('import pandas as pd', lines[5])
      assert.equals('df = pd.read_csv("data.csv")', lines[6])
      assert.equals("print(df.head())", lines[7])
      assert.equals("```", lines[8])
    end)

    it("sets cell buf_start and buf_end", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      buf_mod.notebook_to_lines(notebook)

      -- markdown cell: lines 0-1 (2 lines)
      assert.equals(0, notebook.cells[1].buf_start)
      assert.equals(2, notebook.cells[1].buf_end)

      -- code cell: line 3 (```python) through line 7 (```)
      assert.equals(3, notebook.cells[2].buf_start)
      assert.equals(8, notebook.cells[2].buf_end)
    end)
  end)

  describe("serialize", function()
    it("round-trips without data loss", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      local serialized = notebook:serialize()

      -- Re-parse
      local notebook2 = Notebook.parse(serialized)
      assert.equals(#notebook.cells, #notebook2.cells)

      for i, cell in ipairs(notebook.cells) do
        local cell2 = notebook2.cells[i]
        assert.equals(cell.cell_type, cell2.cell_type)
        assert.equals(cell:get_source(), cell2:get_source())
        assert.equals(cell.id, cell2.id)
        if cell.cell_type == "code" then
          assert.equals(#cell:get_outputs(), #cell2:get_outputs())
          assert.equals(cell:get_execution_count(), cell2:get_execution_count())
        end
      end
    end)
  end)

  describe("cell_at_line", function()
    it("finds the correct cell for a buffer line", function()
      local f = io.open(fixture_path, "r")
      local content = f:read("*a")
      f:close()

      local notebook = Notebook.parse(content, fixture_path)
      buf_mod.notebook_to_lines(notebook)

      assert.equals(1, notebook:cell_at_line(0)) -- markdown cell
      assert.equals(1, notebook:cell_at_line(1))
      assert.equals(2, notebook:cell_at_line(3)) -- code cell fence
      assert.equals(2, notebook:cell_at_line(5)) -- code cell content
    end)
  end)
end)
