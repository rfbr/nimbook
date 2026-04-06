---@class nimbook.Cell
---@field raw table The raw cell table from .ipynb JSON (preserved exactly)
---@field id string Cell ID
---@field cell_type "code"|"markdown"|"raw"
---@field buf_start integer|nil Start line in buffer (0-indexed)
---@field buf_end integer|nil End line in buffer (0-indexed, exclusive)
---@field outputs_visible boolean Whether outputs are displayed
local Cell = {}
Cell.__index = Cell

---@param raw table Raw cell data from .ipynb JSON
---@return nimbook.Cell
function Cell.new(raw)
  local self = setmetatable({}, Cell)
  self.raw = raw
  self.id = raw.id or Cell.generate_id()
  self.cell_type = raw.cell_type
  self.buf_start = nil
  self.buf_end = nil
  self.outputs_visible = true
  -- Ensure id is set in raw
  if not raw.id then
    raw.id = self.id
  end
  return self
end

--- Get the cell source as a single string
---@return string
function Cell:get_source()
  local src = self.raw.source
  if type(src) == "table" then
    return table.concat(src)
  end
  return src or ""
end

--- Set the cell source from a single string
---@param text string
function Cell:set_source(text)
  -- nbformat stores source as array of lines (each ending with \n except possibly the last)
  if text == "" then
    self.raw.source = { "" }
    return
  end
  local lines = {}
  -- Split on newlines, keeping \n as part of each line
  local has_trailing_nl = text:sub(-1) == "\n"
  for line in text:gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line .. "\n"
  end
  -- If text doesn't end with \n, grab the last segment
  if not has_trailing_nl then
    local last = text:match("[^\n]*$")
    if last and last ~= "" then
      lines[#lines + 1] = last
    end
  end
  if #lines == 0 then
    lines = { "" }
  end
  self.raw.source = lines
end

--- Get outputs (code cells only)
---@return table[]
function Cell:get_outputs()
  if self.cell_type ~= "code" then
    return {}
  end
  return self.raw.outputs or {}
end

--- Set outputs (code cells only)
---@param outputs table[]
function Cell:set_outputs(outputs)
  if self.cell_type == "code" then
    self.raw.outputs = outputs
  end
end

--- Clear outputs and execution count
function Cell:clear_outputs()
  if self.cell_type == "code" then
    self.raw.outputs = {}
    self.raw.execution_count = vim.NIL
  end
end

--- Get execution count
---@return integer|nil
function Cell:get_execution_count()
  if self.cell_type ~= "code" then
    return nil
  end
  local ec = self.raw.execution_count
  if ec == vim.NIL then
    return nil
  end
  return ec
end

--- Set execution count
---@param count integer|nil
function Cell:set_execution_count(count)
  if self.cell_type == "code" then
    self.raw.execution_count = count or vim.NIL
  end
end

--- Get source lines for display in buffer (without trailing newlines)
---@return string[]
function Cell:get_display_lines()
  local source = self:get_source()
  -- Remove trailing newline for display
  if source:sub(-1) == "\n" then
    source = source:sub(1, -2)
  end
  if source == "" then
    return { "" }
  end
  return vim.split(source, "\n", { plain = true })
end

--- Generate a simple cell ID (UUID-like)
---@return string
function Cell.generate_id()
  local template = "xxxxxxxx"
  return (template:gsub("x", function()
    return string.format("%x", math.random(0, 15))
  end))
end

--- Create a new empty code cell
---@return nimbook.Cell
function Cell.new_code()
  return Cell.new({
    cell_type = "code",
    source = { "" },
    metadata = {},
    outputs = {},
    execution_count = vim.NIL,
  })
end

--- Create a new empty markdown cell
---@return nimbook.Cell
function Cell.new_markdown()
  return Cell.new({
    cell_type = "markdown",
    source = { "" },
    metadata = {},
  })
end

return Cell
