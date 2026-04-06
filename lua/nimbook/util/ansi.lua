--- ANSI escape code parser
--- Converts ANSI-colored text into Neovim highlight chunks for virtual text.
local M = {}

-- Map ANSI color codes to Neovim highlight groups
local ansi_to_hl = {
  ["0"] = "Normal",
  ["1"] = "Bold",
  ["30"] = "NimbookAnsiBlack",
  ["31"] = "NimbookAnsiRed",
  ["32"] = "NimbookAnsiGreen",
  ["33"] = "NimbookAnsiYellow",
  ["34"] = "NimbookAnsiBlue",
  ["35"] = "NimbookAnsiMagenta",
  ["36"] = "NimbookAnsiCyan",
  ["37"] = "NimbookAnsiWhite",
  ["90"] = "NimbookAnsiBrightBlack",
  ["91"] = "NimbookAnsiBrightRed",
  ["92"] = "NimbookAnsiBrightGreen",
  ["93"] = "NimbookAnsiBrightYellow",
  ["94"] = "NimbookAnsiBrightBlue",
  ["95"] = "NimbookAnsiBrightMagenta",
  ["96"] = "NimbookAnsiBrightCyan",
  ["97"] = "NimbookAnsiBrightWhite",
}

--- Set up ANSI highlight groups
function M.setup_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "NimbookAnsiBlack", { fg = "#555555", default = true })
  hl(0, "NimbookAnsiRed", { fg = "#ef4444", default = true })
  hl(0, "NimbookAnsiGreen", { fg = "#22c55e", default = true })
  hl(0, "NimbookAnsiYellow", { fg = "#eab308", default = true })
  hl(0, "NimbookAnsiBlue", { fg = "#3b82f6", default = true })
  hl(0, "NimbookAnsiMagenta", { fg = "#a855f7", default = true })
  hl(0, "NimbookAnsiCyan", { fg = "#06b6d4", default = true })
  hl(0, "NimbookAnsiWhite", { fg = "#e5e5e5", default = true })
  hl(0, "NimbookAnsiBrightBlack", { fg = "#737373", default = true })
  hl(0, "NimbookAnsiBrightRed", { fg = "#f87171", default = true })
  hl(0, "NimbookAnsiBrightGreen", { fg = "#4ade80", default = true })
  hl(0, "NimbookAnsiBrightYellow", { fg = "#facc15", default = true })
  hl(0, "NimbookAnsiBrightBlue", { fg = "#60a5fa", default = true })
  hl(0, "NimbookAnsiBrightMagenta", { fg = "#c084fc", default = true })
  hl(0, "NimbookAnsiBrightCyan", { fg = "#22d3ee", default = true })
  hl(0, "NimbookAnsiBrightWhite", { fg = "#ffffff", default = true })
end

--- Parse a string with ANSI escape codes into virtual text chunks
--- Each chunk is {text, highlight_group}
---@param text string Text possibly containing ANSI escape codes
---@param default_hl? string Default highlight group for unstyled text
---@return table[] chunks Array of {text, hl} pairs
function M.parse(text, default_hl)
  default_hl = default_hl or "NimbookOutput"
  local chunks = {}
  local current_hl = default_hl
  local pos = 1
  local len = #text

  while pos <= len do
    -- Find next escape sequence
    local esc_start = text:find("\27%[", pos)

    if not esc_start then
      -- No more escapes, add remaining text
      local remaining = text:sub(pos)
      if #remaining > 0 then
        chunks[#chunks + 1] = { remaining, current_hl }
      end
      break
    end

    -- Add text before escape
    if esc_start > pos then
      chunks[#chunks + 1] = { text:sub(pos, esc_start - 1), current_hl }
    end

    -- Parse the escape sequence
    local seq_end = text:find("m", esc_start + 2)
    if seq_end then
      local codes_str = text:sub(esc_start + 2, seq_end - 1)
      -- Handle semicolon-separated codes
      for code in codes_str:gmatch("([^;]+)") do
        if code == "0" or code == "" then
          current_hl = default_hl
        elseif code == "1" then
          -- Bold: we could combine with current color, but keep it simple
          current_hl = "Bold"
        elseif ansi_to_hl[code] then
          current_hl = ansi_to_hl[code]
        end
      end
      pos = seq_end + 1
    else
      -- Malformed escape, skip the ESC[
      pos = esc_start + 2
    end
  end

  -- Merge adjacent chunks with the same highlight
  local merged = {}
  for _, chunk in ipairs(chunks) do
    if #merged > 0 and merged[#merged][2] == chunk[2] then
      merged[#merged][1] = merged[#merged][1] .. chunk[1]
    else
      merged[#merged + 1] = chunk
    end
  end

  return merged
end

--- Strip all ANSI escape codes from a string
---@param text string
---@return string
function M.strip(text)
  return text:gsub("\27%[[%d;]*m", "")
end

return M
