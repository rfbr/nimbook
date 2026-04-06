--- Terminal graphics capability detection and dispatch
--- Detects which image protocol the terminal supports and provides a unified API.
local M = {}

---@alias nimbook.GraphicsBackend "kitty"|"sixel"|"none"

---@type nimbook.GraphicsBackend|nil
local detected_backend = nil

--- Detect the terminal's graphics capabilities
---@return nimbook.GraphicsBackend
function M.detect()
  if detected_backend then
    return detected_backend
  end

  -- Check for Kitty graphics protocol support
  if M._detect_kitty() then
    detected_backend = "kitty"
    return detected_backend
  end

  -- Check for Sixel support
  if M._detect_sixel() then
    detected_backend = "sixel"
    return detected_backend
  end

  detected_backend = "none"
  return detected_backend
end

--- Check for Kitty graphics protocol support via environment
---@return boolean
function M._detect_kitty()
  -- Kitty terminal
  if vim.env.KITTY_WINDOW_ID then
    return true
  end
  -- Ghostty supports Kitty graphics protocol
  if vim.env.GHOSTTY_RESOURCES_DIR then
    return true
  end
  -- WezTerm supports Kitty graphics protocol
  if vim.env.TERM_PROGRAM == "WezTerm" then
    return true
  end
  -- Check TERM for kitty
  local term = vim.env.TERM or ""
  if term:match("xterm%-kitty") then
    return true
  end
  return false
end

--- Check for Sixel support via environment heuristics
---@return boolean
function M._detect_sixel()
  local term = vim.env.TERM or ""
  local term_program = vim.env.TERM_PROGRAM or ""

  -- Terminals known to support Sixel
  if term_program == "foot" then
    return true
  end
  if term:match("xterm") and vim.env.XTERM_VERSION then
    -- Recent XTerm supports Sixel
    return true
  end
  if term:match("mlterm") then
    return true
  end
  -- WezTerm also supports Sixel (but we prefer Kitty above)
  -- contour, etc.

  return false
end

--- Check if we're inside tmux (need passthrough wrapping)
---@return boolean
function M.in_tmux()
  return vim.env.TMUX ~= nil
end

--- Get the appropriate graphics renderer module
---@return table|nil renderer Module with display/clear functions, or nil for text fallback
function M.get_renderer()
  local backend = M.detect()
  if backend == "kitty" then
    return require("nimbook.graphics.kitty")
  elseif backend == "sixel" then
    return require("nimbook.graphics.sixel")
  end
  return nil
end

--- Wrap an escape sequence for tmux passthrough if needed
---@param seq string Escape sequence
---@return string wrapped
function M.tmux_wrap(seq)
  if not M.in_tmux() then
    return seq
  end
  -- tmux passthrough: \ePtmux;\e{original_escape}\e\\
  -- Double any ESC characters inside the sequence
  local inner = seq:gsub("\027", "\027\027")
  return "\027Ptmux;" .. inner .. "\027\\"
end

--- Get terminal cell size in pixels (needed for image scaling)
---@return integer|nil cell_width, integer|nil cell_height
function M.get_cell_size()
  -- Try environment variables first (set by some terminals)
  -- Kitty provides this via escape sequence, but for simplicity
  -- we use heuristics based on common defaults
  local cols = vim.o.columns
  local lines = vim.o.lines

  -- Try ioctl-based approach via stty
  local result = vim.fn.system("stty size 2>/dev/null")
  if vim.v.shell_error == 0 then
    local term_lines, term_cols = result:match("(%d+)%s+(%d+)")
    if term_lines and term_cols then
      lines = tonumber(term_lines) or lines
      cols = tonumber(term_cols) or cols
    end
  end

  -- Try to get pixel dimensions from environment or typical defaults
  -- Most modern terminals at default settings: ~8px wide, ~16px tall per cell
  local cell_w = 8
  local cell_h = 16

  -- Some terminals set COLUMNS_PIXELS/LINES_PIXELS or we can infer from window size
  local wpx = tonumber(vim.env.WINDOWPIXELS_W)
  local hpx = tonumber(vim.env.WINDOWPIXELS_H)
  if wpx and hpx and cols > 0 and lines > 0 then
    cell_w = math.floor(wpx / cols)
    cell_h = math.floor(hpx / lines)
  end

  return cell_w, cell_h
end

return M
