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

-- Diacritics table for Unicode placeholder row/column encoding.
-- Maps integer 0..N to a Unicode combining character codepoint.
-- Source: Kitty's rowcolumn-diacritics.txt (combining class 230 marks).
-- stylua: ignore
local diacritics = {
  0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F,
  0x0346, 0x034A, 0x034B, 0x034C, 0x0350, 0x0351, 0x0352, 0x0357,
  0x035B, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
  0x036A, 0x036B, 0x036C, 0x036D, 0x036E, 0x036F, 0x0483, 0x0484,
  0x0485, 0x0486, 0x0487, 0x0592, 0x0593, 0x0594, 0x0595, 0x0597,
  0x0598, 0x0599, 0x059C, 0x059D, 0x059E, 0x059F, 0x05A0, 0x05A1,
  0x05A8, 0x05A9, 0x05AB, 0x05AC, 0x05AF, 0x05C4, 0x0610, 0x0611,
  0x0612, 0x0613, 0x0614, 0x0615, 0x0616, 0x0617, 0x0657, 0x0658,
  0x0659, 0x065A, 0x065B, 0x065D, 0x065E, 0x06D6, 0x06D7, 0x06D8,
  0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DF, 0x06E0, 0x06E1, 0x06E2,
  0x06E4, 0x06E7, 0x06E8, 0x06EB, 0x06EC, 0x0730, 0x0732, 0x0733,
  0x0735, 0x0736, 0x073A, 0x073D, 0x073F, 0x0740, 0x0741, 0x0743,
  0x0745, 0x0747, 0x0749, 0x074A, 0x07EB, 0x07EC, 0x07ED, 0x07EE,
  0x07EF, 0x07F0, 0x07F1, 0x07F3, 0x0816, 0x0817, 0x0818, 0x0819,
  0x081B, 0x081C, 0x081D, 0x081E, 0x081F, 0x0820, 0x0821, 0x0822,
  0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082A, 0x082B, 0x082C,
  0x082D, 0x0951, 0x0953, 0x0954, 0x0F82, 0x0F83, 0x0F86, 0x0F87,
  0x135D, 0x135E, 0x135F, 0x17DD, 0x193A, 0x1A17, 0x1A75, 0x1A76,
  0x1A77, 0x1A78, 0x1A79, 0x1A7A, 0x1A7B, 0x1A7C, 0x1B6B, 0x1B6D,
  0x1B6E, 0x1B6F, 0x1B70, 0x1B71, 0x1B72, 0x1B73, 0x1CD0, 0x1CD1,
  0x1CD2, 0x1CDA, 0x1CDB, 0x1CE0, 0x1DC0, 0x1DC1, 0x1DC3, 0x1DC4,
  0x1DC5, 0x1DC6, 0x1DC7, 0x1DC8, 0x1DC9, 0x1DCB, 0x1DCC, 0x1DD1,
  0x1DD2, 0x1DD3, 0x1DD4, 0x1DD5, 0x1DD6, 0x1DD7, 0x1DD8, 0x1DD9,
  0x1DDA, 0x1DDB, 0x1DDC, 0x1DDD, 0x1DDE, 0x1DDF, 0x1DE0, 0x1DE1,
  0x1DE2, 0x1DE3, 0x1DE4, 0x1DE5, 0x1DE6, 0x1DFE, 0x20D0, 0x20D1,
  0x20D4, 0x20D5, 0x20D6, 0x20D7, 0x20DB, 0x20DC, 0x20E1, 0x20E7,
  0x20E9, 0x20F0, 0x2CEF, 0x2CF0, 0x2CF1, 0x2DE0, 0x2DE1, 0x2DE2,
  0x2DE3, 0x2DE4, 0x2DE5, 0x2DE6, 0x2DE7, 0x2DE8, 0x2DE9, 0x2DEA,
  0x2DEB, 0x2DEC, 0x2DED, 0x2DEE, 0x2DEF, 0x2DF0, 0x2DF1, 0x2DF2,
  0x2DF3, 0x2DF4, 0x2DF5, 0x2DF6, 0x2DF7, 0x2DF8, 0x2DF9, 0x2DFA,
  0x2DFB, 0x2DFC, 0x2DFD, 0x2DFE, 0x2DFF, 0xA66F, 0xA67C, 0xA67D,
  0xA6F0, 0xA6F1, 0xA8E0, 0xA8E1, 0xA8E2, 0xA8E3, 0xA8E4, 0xA8E5,
  0xA8E6, 0xA8E7, 0xA8E8, 0xA8E9, 0xA8EA, 0xA8EB, 0xA8EC, 0xA8ED,
  0xA8EE, 0xA8EF, 0xA8F0, 0xA8F1, 0xAAB0, 0xAAB2, 0xAAB3, 0xAAB7,
  0xAAB8, 0xAABE, 0xAABF, 0xAAC1, 0xFE20, 0xFE21, 0xFE22, 0xFE23,
  0xFE24, 0xFE25, 0xFE26, 0x10A0F, 0x10A38, 0x1D185, 0x1D186,
  0x1D187, 0x1D188, 0x1D189, 0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD,
  0x1D242, 0x1D243, 0x1D244,
}

--- Pre-compute UTF-8 strings for diacritics (1-indexed, value at index i = diacritic for i-1)
local diacritic_chars = {}
for i, cp in ipairs(diacritics) do
  diacritic_chars[i - 1] = vim.fn.nr2char(cp)
end

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

--- Build a placeholder character with row and column diacritics
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@return string Single placeholder character with combining marks
local function placeholder_cell(row, col)
  return PLACEHOLDER .. (diacritic_chars[row] or diacritic_chars[0]) .. (diacritic_chars[col] or diacritic_chars[0])
end

--- Build a full row of placeholder characters
---@param row integer 0-indexed row
---@param cols integer Number of columns
---@return string All placeholder characters for this row
local function placeholder_row(row, cols)
  local parts = {}
  for col = 0, cols - 1 do
    parts[#parts + 1] = placeholder_cell(row, col)
  end
  return table.concat(parts)
end

--- Get or create a highlight group encoding image_id and placement_id
--- Kitty reads the fg color as image_id and underline color as placement_id.
---@param image_id integer
---@param placement_id integer
---@return string hl_group name
local function get_image_hl(image_id, placement_id)
  local name = string.format("NimbookImg%d_%d", image_id, placement_id)
  vim.api.nvim_set_hl(0, name, {
    fg = string.format("#%06x", image_id),
    sp = string.format("#%06x", placement_id),
    underline = true, -- required for terminal to emit the sp (underline) color
  })
  return name
end

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
        a = "t",     -- transmit only (no display)
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
    a = "t",     -- transmit only (no display)
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

  -- Transmit the image (no display -- placeholders handle positioning)
  transmit_file(pl.image_id, tmpfile)

  -- Create a virtual placement: the terminal will render the image wherever
  -- it sees U+10EEEE characters with matching fg color (= image_id).
  local display_cmd = kitty_cmd({
    a = "p",          -- place
    i = pl.image_id,
    p = pl.id,
    U = 1,            -- Unicode placeholder mode
    c = display_cols, -- columns
    r = display_rows, -- rows
    q = 2,
  })
  io.stdout:write(display_cmd)
  io.stdout:flush()

  -- Build virtual text lines with Unicode placeholders.
  -- Each U+10EEEE char gets combining diacritics encoding row/column.
  -- The fg color encodes image_id; underline color encodes placement_id.
  local hl = get_image_hl(pl.image_id, pl.id)
  local virt_lines = {}

  for row = 0, display_rows - 1 do
    local row_text = placeholder_row(row, display_cols)
    virt_lines[#virt_lines + 1] = {
      { row_text, hl },
    }
  end

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
