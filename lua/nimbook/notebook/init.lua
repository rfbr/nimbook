local Cell = require("nimbook.notebook.cell")

---@class nimbook.Notebook
---@field raw table The full parsed .ipynb JSON (preserved exactly)
---@field cells nimbook.Cell[]
---@field filepath string|nil Path to the .ipynb file
local Notebook = {}
Notebook.__index = Notebook

--- Parse a .ipynb JSON string into a Notebook
---@param json_str string
---@param filepath? string
---@return nimbook.Notebook
function Notebook.parse(json_str, filepath)
  local ok, raw = pcall(vim.json.decode, json_str)
  if not ok then
    error("nimbook: failed to parse .ipynb JSON: " .. tostring(raw))
  end

  local self = setmetatable({}, Notebook)
  self.raw = raw
  self.filepath = filepath
  self.cells = {}

  for i, cell_raw in ipairs(raw.cells or {}) do
    self.cells[i] = Cell.new(cell_raw)
  end

  return self
end

--- Create an empty notebook
---@param filepath? string
---@return nimbook.Notebook
function Notebook.empty(filepath)
  local raw = {
    cells = {},
    metadata = {
      kernelspec = {
        display_name = "Python 3",
        language = "python",
        name = "python3",
      },
      language_info = {
        name = "python",
        version = "3.12.0",
      },
    },
    nbformat = 4,
    nbformat_minor = 5,
  }
  local self = setmetatable({}, Notebook)
  self.raw = raw
  self.filepath = filepath
  self.cells = {}
  return self
end

--- Read a .ipynb file from disk
---@param filepath string
---@return nimbook.Notebook
function Notebook.read(filepath)
  local f = io.open(filepath, "r")
  if not f then
    error("nimbook: cannot open file: " .. filepath)
  end
  local content = f:read("*a")
  f:close()
  return Notebook.parse(content, filepath)
end

--- Serialize the notebook back to JSON string
---@return string
function Notebook:serialize()
  -- Sync cells back to raw
  self.raw.cells = {}
  for i, cell in ipairs(self.cells) do
    self.raw.cells[i] = cell.raw
  end
  -- vim.json.encode produces compact JSON; we want readable output
  -- Use a custom encoder for notebook-style formatting
  return self:_format_json()
end

--- Write the notebook to its filepath
---@param filepath? string Override filepath
function Notebook:write(filepath)
  filepath = filepath or self.filepath
  if not filepath then
    error("nimbook: no filepath set for notebook")
  end
  local json_str = self:serialize()
  local f = io.open(filepath, "w")
  if not f then
    error("nimbook: cannot write file: " .. filepath)
  end
  f:write(json_str)
  f:write("\n")
  f:close()
  self.filepath = filepath
end

--- Get the kernel language from metadata
---@return string
function Notebook:get_language()
  local info = self.raw.metadata and self.raw.metadata.language_info
  if info and info.name then
    return info.name
  end
  local ks = self.raw.metadata and self.raw.metadata.kernelspec
  if ks and ks.language then
    return ks.language
  end
  return "python"
end

--- Insert a cell at a given position
---@param index integer Position (1-based)
---@param cell nimbook.Cell
function Notebook:insert_cell(index, cell)
  table.insert(self.cells, index, cell)
end

--- Remove a cell at a given position
---@param index integer Position (1-based)
---@return nimbook.Cell The removed cell
function Notebook:remove_cell(index)
  if #self.cells <= 1 then
    error("nimbook: cannot remove the last cell")
  end
  return table.remove(self.cells, index)
end

--- Move a cell from one position to another
---@param from integer
---@param to integer
function Notebook:move_cell(from, to)
  if from == to then
    return
  end
  local cell = table.remove(self.cells, from)
  table.insert(self.cells, to, cell)
end

--- Find the cell index containing a buffer line
---@param line integer 0-indexed buffer line
---@return integer|nil Cell index (1-based)
function Notebook:cell_at_line(line)
  for i, cell in ipairs(self.cells) do
    if cell.buf_start and cell.buf_end then
      if line >= cell.buf_start and line < cell.buf_end then
        return i
      end
    end
  end
  return nil
end

--- Format the notebook as indented JSON matching Jupyter's output style
---@return string
function Notebook:_format_json()
  -- We use vim.json.encode then reformat, because LuaJIT doesn't have
  -- a built-in pretty-printer with the exact Jupyter style.
  -- However, for lossless round-trip the exact formatting doesn't matter
  -- as long as the data is identical. We use 1-space indent for readability.
  local json = vim.json.encode(self.raw)
  -- Pretty-print with consistent formatting
  return self:_pretty_print(json)
end

--- Simple JSON pretty-printer that produces Jupyter-compatible output
---@param json string Compact JSON string
---@return string Pretty-printed JSON
function Notebook:_pretty_print(json)
  local result = {}
  local indent = 0
  local in_string = false
  local escape_next = false
  local i = 1
  local len = #json

  while i <= len do
    local char = json:sub(i, i)

    if escape_next then
      result[#result + 1] = char
      escape_next = false
    elseif char == "\\" and in_string then
      result[#result + 1] = char
      escape_next = true
    elseif char == '"' then
      result[#result + 1] = char
      in_string = not in_string
    elseif in_string then
      result[#result + 1] = char
    elseif char == "{" or char == "[" then
      result[#result + 1] = char
      -- Check if the next non-whitespace is the closing bracket (empty container)
      local next_char = json:match("^%s*(.)", i + 1)
      if (char == "{" and next_char == "}") or (char == "[" and next_char == "]") then
        -- Empty container, keep on same line
        local close_pos = json:find(char == "{" and "}" or "%]", i + 1)
        result[#result + 1] = json:sub(i + 1, close_pos)
        i = close_pos
      else
        indent = indent + 1
        result[#result + 1] = "\n" .. string.rep(" ", indent)
      end
    elseif char == "}" or char == "]" then
      indent = indent - 1
      result[#result + 1] = "\n" .. string.rep(" ", indent)
      result[#result + 1] = char
    elseif char == "," then
      result[#result + 1] = ","
      result[#result + 1] = "\n" .. string.rep(" ", indent)
    elseif char == ":" then
      result[#result + 1] = ": "
    elseif char ~= " " and char ~= "\n" and char ~= "\r" and char ~= "\t" then
      result[#result + 1] = char
    end

    i = i + 1
  end

  return table.concat(result)
end

return Notebook
