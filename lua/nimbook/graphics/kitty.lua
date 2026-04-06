--- Kitty graphics protocol implementation
--- Transmits and displays images inline in terminals that support the Kitty graphics protocol
--- (Kitty, Ghostty, WezTerm).
---
--- Protocol reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/
---
--- Strategy: We use Unicode placeholder mode. Images are transmitted to the terminal
--- and then placed using a virtual text row of Unicode placeholder characters (U+10EEEE).
--- This allows images to coexist with Neovim's buffer model -- placeholders live in
--- extmark virtual lines, so they scroll, resize, and get cleaned up naturally.
local base64 = require("nimbook.util.base64")
local placement = require("nimbook.graphics.placement")
local graphics = require("nimbook.graphics")

local M = {}

-- Kitty graphics protocol escape sequences
local APC = "\027_G"
local ST = "\027\\"

--- Build a Kitty graphics command string
---@param params table Key-value parameters
---@param payload? string Base64 payload
---@return string
local function kitty_cmd(params, payload)
  local parts = {}
  for k, v in pairs(params) do
    parts[#parts + 1] = k .. "=" .. tostring(v)
  end
  local cmd = APC .. table.concat(parts, ",")
  if payload and #payload > 0 then
    cmd = cmd .. ";" .. payload
  end
  cmd = cmd .. ST
  return graphics.tmux_wrap(cmd)
end

--- Transmit image data to the terminal using chunked transfer
--- Kitty protocol limits each payload to 4096 bytes, so we chunk larger images.
---@param image_id integer Unique image ID
---@param b64_data string Base64-encoded image data
---@param fmt? string Format: 100=PNG (default), 32=RGBA, 24=RGB
local function transmit_chunked(image_id, b64_data, fmt)
  fmt = fmt or "100" -- PNG

  local chunk_size = 4096
  local total = #b64_data
  local offset = 1

  while offset <= total do
    local chunk = b64_data:sub(offset, offset + chunk_size - 1)
    local is_last = (offset + chunk_size - 1) >= total
    local more = is_last and 0 or 1

    local params
    if offset == 1 then
      -- First chunk includes image metadata
      params = {
        a = "T",     -- transmit action
        f = fmt,     -- format
        i = image_id,
        q = 2,       -- suppress response
        m = more,    -- more chunks coming?
      }
    else
      params = {
        i = image_id,
        q = 2,
        m = more,
      }
    end

    local cmd = kitty_cmd(params, chunk)
    io.stdout:write(cmd)

    offset = offset + chunk_size
  end

  io.stdout:flush()
end

--- Transmit an image from a file path
---@param image_id integer
---@param filepath string Path to image file
local function transmit_file(image_id, filepath)
  local path_b64 = base64.encode(filepath)
  local cmd = kitty_cmd({
    a = "T",     -- transmit
    f = 100,     -- PNG
    t = "f",     -- file transmission
    i = image_id,
    q = 2,       -- quiet
  }, path_b64)
  io.stdout:write(cmd)
  io.stdout:flush()
end

--- Delete an image from the terminal
---@param image_id integer
local function delete_image(image_id)
  local cmd = kitty_cmd({
    a = "d",       -- delete
    d = "I",       -- by image ID
    i = image_id,
    q = 2,
  })
  io.stdout:write(cmd)
  io.stdout:flush()
end

--- Display an image that was decoded from notebook output
--- Returns virtual text lines containing Unicode placeholders for the image.
---@param buf integer Buffer handle
---@param cell_idx integer Cell index
---@param image_data string Raw image bytes (decoded from base64)
---@param opts? { max_width?: integer, max_height?: integer }
---@return table[] virt_lines Virtual text lines for extmarks
---@return nimbook.ImagePlacement placement_info
function M.display(buf, cell_idx, image_data, opts)
  opts = opts or {}
  local max_cols = opts.max_width or (vim.o.columns - 6) -- leave room for borders
  local max_rows = opts.max_height or 20

  -- Get cell size for pixel calculations
  local cell_w, cell_h = graphics.get_cell_size()

  -- Write to temp file for file-based transmission (more reliable for large images)
  local tmpfile = placement.write_temp(image_data, "png")

  -- Try to determine image dimensions
  -- Use `identify` (ImageMagick) or `file` command as fallback
  local img_w, img_h = M._get_image_size(tmpfile)
  if not img_w then
    -- Default to reasonable size
    img_w = max_cols * cell_w
    img_h = max_rows * cell_h
  end

  -- Calculate display size in terminal cells
  local display_cols = math.min(max_cols, math.ceil(img_w / cell_w))
  local display_rows = math.ceil((img_h / img_w) * display_cols * (cell_w / cell_h))
  display_rows = math.min(max_rows, math.max(1, display_rows))

  -- Create placement
  local pl = placement.create({
    buf = buf,
    line = 0, -- will be set by caller
    cell_idx = cell_idx,
    width = display_cols,
    height = display_rows,
    tmpfile = tmpfile,
  })

  -- Transmit the image
  transmit_file(pl.image_id, tmpfile)

  -- Build virtual text lines with Unicode placeholders
  -- The Unicode placeholder character is U+10EEEE (from Kitty's private use area)
  -- Each placeholder char represents one cell of the image
  local placeholder = "\u{10EEEE}"
  local virt_lines = {}

  for row = 0, display_rows - 1 do
    local row_text = string.rep(placeholder, display_cols)
    -- Use Kitty's placement via a display command for this row
    -- Actually, the simpler approach: use virtual placement with row/col info
    -- For virtual placement, we send a display command once and use diacritics
    -- to indicate position. But this is complex. Simpler: use the "direct"
    -- approach where we just show the image at a specific position.
    virt_lines[#virt_lines + 1] = {
      { row_text, "NimbookImage" },
    }
  end

  -- Send the display/placement command
  -- p=1 means placement ID 1 for this image
  -- U=1 means use Unicode placeholders
  local display_cmd = kitty_cmd({
    a = "p",          -- place
    i = pl.image_id,
    p = pl.id,
    U = 1,            -- Unicode placement mode
    c = display_cols, -- columns
    r = display_rows, -- rows
    q = 2,
  })
  io.stdout:write(display_cmd)
  io.stdout:flush()

  placement.show(pl.id)

  return virt_lines, pl
end

--- Clear a specific image placement from the terminal
---@param pl nimbook.ImagePlacement
function M.clear(pl)
  delete_image(pl.image_id)
end

--- Clear all images for a buffer
---@param buf integer
function M.clear_buffer(buf)
  placement.remove_for_buffer(buf, M.clear)
end

--- Clear images for a specific cell
---@param buf integer
---@param cell_idx integer
function M.clear_cell(buf, cell_idx)
  placement.remove_for_cell(buf, cell_idx, M.clear)
end

--- Get image dimensions using available system tools
---@param filepath string
---@return integer|nil width, integer|nil height
function M._get_image_size(filepath)
  -- Try `identify` (ImageMagick)
  local result = vim.fn.system(string.format("identify -format '%%w %%h' %s 2>/dev/null", vim.fn.shellescape(filepath)))
  if vim.v.shell_error == 0 then
    local w, h = result:match("(%d+)%s+(%d+)")
    if w and h then
      return tonumber(w), tonumber(h)
    end
  end

  -- Try `file` command (less reliable but widely available)
  result = vim.fn.system(string.format("file %s 2>/dev/null", vim.fn.shellescape(filepath)))
  if vim.v.shell_error == 0 then
    local w, h = result:match("(%d+)%s*x%s*(%d+)")
    if w and h then
      return tonumber(w), tonumber(h)
    end
  end

  -- Try reading PNG header directly (PNG files start with IHDR chunk at offset 16)
  local f = io.open(filepath, "rb")
  if f then
    local header = f:read(24)
    f:close()
    if header and #header >= 24 then
      -- PNG signature + IHDR: bytes 16-19 = width, 20-23 = height (big-endian)
      local b = { header:byte(17, 24) }
      if #b == 8 then
        local w = b[1] * 16777216 + b[2] * 65536 + b[3] * 256 + b[4]
        local h = b[5] * 16777216 + b[6] * 65536 + b[7] * 256 + b[8]
        if w > 0 and w < 100000 and h > 0 and h < 100000 then
          return w, h
        end
      end
    end
  end

  return nil, nil
end

return M
