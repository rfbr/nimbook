--- Basic HTML-to-text conversion
--- Handles common HTML elements found in Jupyter outputs (tables, paragraphs, etc.)
local M = {}

--- Convert HTML to plain text
---@param html string HTML string
---@return string text Plain text approximation
function M.to_text(html)
  local text = html

  -- Remove scripts and styles entirely
  text = text:gsub("<script.-</script>", "")
  text = text:gsub("<style.-</style>", "")

  -- Block elements that add newlines
  text = text:gsub("<br%s*/?>", "\n")
  text = text:gsub("<hr%s*/?>", "\n" .. string.rep("-", 40) .. "\n")
  text = text:gsub("</p>", "\n\n")
  text = text:gsub("</div>", "\n")
  text = text:gsub("</h[1-6]>", "\n\n")
  text = text:gsub("</li>", "\n")
  text = text:gsub("</tr>", "\n")
  text = text:gsub("</td>", "\t")
  text = text:gsub("</th>", "\t")

  -- Headings: add a prefix
  text = text:gsub("<h1[^>]*>", "# ")
  text = text:gsub("<h2[^>]*>", "## ")
  text = text:gsub("<h3[^>]*>", "### ")
  text = text:gsub("<h[4-6][^>]*>", "#### ")

  -- Lists
  text = text:gsub("<li[^>]*>", "  - ")

  -- Bold/italic markers
  text = text:gsub("<b[^>]*>", "*")
  text = text:gsub("</b>", "*")
  text = text:gsub("<strong[^>]*>", "*")
  text = text:gsub("</strong>", "*")
  text = text:gsub("<i[^>]*>", "_")
  text = text:gsub("</i>", "_")
  text = text:gsub("<em[^>]*>", "_")
  text = text:gsub("</em>", "_")

  -- Code
  text = text:gsub("<code[^>]*>", "`")
  text = text:gsub("</code>", "`")
  text = text:gsub("<pre[^>]*>", "\n")
  text = text:gsub("</pre>", "\n")

  -- Strip remaining tags
  text = text:gsub("<[^>]+>", "")

  -- Decode common HTML entities
  text = text:gsub("&amp;", "&")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&apos;", "'")
  text = text:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then
      return string.char(num)
    end
    return ""
  end)
  text = text:gsub("&nbsp;", " ")

  -- Clean up excessive whitespace
  text = text:gsub("\n%s*\n%s*\n", "\n\n")
  text = text:gsub("^\n+", "")
  text = text:gsub("\n+$", "")

  return text
end

--- Convert an HTML table to aligned text columns
--- Handles <table>, <tr>, <th>, <td>
---@param html string HTML containing a table
---@return string text Aligned text table
function M.table_to_text(html)
  local rows = {}

  -- Extract rows
  for row_html in html:gmatch("<tr[^>]*>(.-)</tr>") do
    local cells = {}
    -- Match both th and td
    for cell_html in row_html:gmatch("<t[hd][^>]*>(.-)</t[hd]>") do
      -- Strip inner HTML tags
      local cell_text = cell_html:gsub("<[^>]+>", "")
      cell_text = cell_text:gsub("&nbsp;", " ")
      cell_text = vim.trim(cell_text)
      cells[#cells + 1] = cell_text
    end
    if #cells > 0 then
      rows[#rows + 1] = cells
    end
  end

  if #rows == 0 then
    return M.to_text(html)
  end

  -- Calculate column widths
  local col_widths = {}
  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      col_widths[i] = math.max(col_widths[i] or 0, #cell)
    end
  end

  -- Format rows
  local lines = {}
  for row_idx, row in ipairs(rows) do
    local parts = {}
    for i, cell in ipairs(row) do
      local width = col_widths[i] or #cell
      parts[#parts + 1] = cell .. string.rep(" ", width - #cell)
    end
    lines[#lines + 1] = table.concat(parts, "  ")

    -- Add separator after header row
    if row_idx == 1 then
      local sep_parts = {}
      for i = 1, #col_widths do
        sep_parts[#sep_parts + 1] = string.rep("-", col_widths[i])
      end
      lines[#lines + 1] = table.concat(sep_parts, "  ")
    end
  end

  return table.concat(lines, "\n")
end

return M
