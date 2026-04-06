--- Export notebook to other formats
--- Supports .py (percent-format script) and .md (Markdown document).
local state = require("nimbook.state")
local buf_sync = require("nimbook.render.buffer")

local M = {}

--- Export the current notebook
---@param format "py"|"md"|"html" Target format
---@param filepath? string Output path (defaults to notebook path with new extension)
function M.export(format, filepath)
  local buf = vim.api.nvim_get_current_buf()
  local notebook = state.get(buf)
  if not notebook then
    vim.notify("nimbook: no notebook in current buffer", vim.log.levels.ERROR)
    return
  end

  -- Sync latest edits
  buf_sync.sync_from_buffer(notebook, buf)

  local content
  if format == "py" then
    content = M.to_python(notebook)
  elseif format == "md" then
    content = M.to_markdown(notebook)
  else
    vim.notify("nimbook: unsupported format: " .. format, vim.log.levels.ERROR)
    return
  end

  -- Determine output path
  if not filepath then
    local base = notebook.filepath or vim.api.nvim_buf_get_name(buf)
    if base == "" then
      base = "notebook"
    end
    filepath = vim.fn.fnamemodify(base, ":r") .. "." .. format
  end

  local f = io.open(filepath, "w")
  if not f then
    vim.notify("nimbook: cannot write to " .. filepath, vim.log.levels.ERROR)
    return
  end
  f:write(content)
  f:close()

  vim.notify("nimbook: exported to " .. filepath, vim.log.levels.INFO)
end

--- Convert notebook to Python percent-format script
--- Compatible with VS Code, Spyder, jupytext
---@param notebook nimbook.Notebook
---@return string
function M.to_python(notebook)
  local parts = {}
  local language = notebook:get_language()

  -- File header
  parts[#parts + 1] = "# ---"
  parts[#parts + 1] = "# jupyter:"
  parts[#parts + 1] = "#   kernelspec:"
  local ks = notebook.raw.metadata and notebook.raw.metadata.kernelspec
  if ks then
    parts[#parts + 1] = "#     display_name: " .. (ks.display_name or "Python 3")
    parts[#parts + 1] = "#     language: " .. (ks.language or language)
    parts[#parts + 1] = "#     name: " .. (ks.name or "python3")
  end
  parts[#parts + 1] = "# ---"
  parts[#parts + 1] = ""

  for i, cell in ipairs(notebook.cells) do
    local source = cell:get_source()
    -- Remove trailing newline
    if source:sub(-1) == "\n" then
      source = source:sub(1, -2)
    end

    if cell.cell_type == "code" then
      parts[#parts + 1] = "# %%"
      parts[#parts + 1] = source
    elseif cell.cell_type == "markdown" then
      parts[#parts + 1] = "# %% [markdown]"
      -- Prefix each line with #
      for line in source:gmatch("([^\n]*)") do
        parts[#parts + 1] = "# " .. line
      end
    elseif cell.cell_type == "raw" then
      parts[#parts + 1] = "# %% [raw]"
      for line in source:gmatch("([^\n]*)") do
        parts[#parts + 1] = "# " .. line
      end
    end

    if i < #notebook.cells then
      parts[#parts + 1] = ""
    end
  end

  parts[#parts + 1] = ""
  return table.concat(parts, "\n")
end

--- Convert notebook to Markdown document
---@param notebook nimbook.Notebook
---@return string
function M.to_markdown(notebook)
  local parts = {}
  local language = notebook:get_language()

  for i, cell in ipairs(notebook.cells) do
    local source = cell:get_source()
    if source:sub(-1) == "\n" then
      source = source:sub(1, -2)
    end

    if cell.cell_type == "code" then
      parts[#parts + 1] = "```" .. language
      parts[#parts + 1] = source
      parts[#parts + 1] = "```"

      -- Include text outputs
      local outputs = cell:get_outputs()
      if #outputs > 0 then
        local output_text = M._outputs_to_text(outputs)
        if output_text ~= "" then
          parts[#parts + 1] = ""
          parts[#parts + 1] = "<details><summary>Output</summary>"
          parts[#parts + 1] = ""
          parts[#parts + 1] = "```"
          parts[#parts + 1] = output_text
          parts[#parts + 1] = "```"
          parts[#parts + 1] = ""
          parts[#parts + 1] = "</details>"
        end
      end
    elseif cell.cell_type == "markdown" then
      parts[#parts + 1] = source
    elseif cell.cell_type == "raw" then
      parts[#parts + 1] = "```"
      parts[#parts + 1] = source
      parts[#parts + 1] = "```"
    end

    if i < #notebook.cells then
      parts[#parts + 1] = ""
    end
  end

  parts[#parts + 1] = ""
  return table.concat(parts, "\n")
end

--- Convert outputs to plain text for export
---@param outputs table[]
---@return string
function M._outputs_to_text(outputs)
  local ansi = require("nimbook.util.ansi")
  local lines = {}

  for _, output in ipairs(outputs) do
    if output.output_type == "stream" then
      local text = output.text
      if type(text) == "table" then
        text = table.concat(text)
      end
      lines[#lines + 1] = ansi.strip(text)

    elseif output.output_type == "execute_result" or output.output_type == "display_data" then
      local data = output.data or {}
      local text = data["text/plain"]
      if text then
        if type(text) == "table" then
          text = table.concat(text)
        end
        lines[#lines + 1] = text
      end

    elseif output.output_type == "error" then
      lines[#lines + 1] = output.ename .. ": " .. output.evalue
    end
  end

  local result = table.concat(lines, "")
  -- Remove trailing newline
  if result:sub(-1) == "\n" then
    result = result:sub(1, -2)
  end
  return result
end

--- Interactive export with format selection
function M.export_interactive()
  vim.ui.select({ "py", "md" }, {
    prompt = "Export format:",
    format_item = function(item)
      if item == "py" then
        return "Python script (.py, percent format)"
      elseif item == "md" then
        return "Markdown document (.md)"
      end
      return item
    end,
  }, function(choice)
    if choice then
      M.export(choice)
    end
  end)
end

return M
