--- Sixel graphics protocol implementation
--- Renders images via Sixel escape sequences for terminals that don't support Kitty.
--- Sixel is supported by: foot, XTerm, mlterm, WezTerm, contour.
---
--- Sixel encoding is complex, so we delegate to an external converter (img2sixel from libsixel,
--- or ImageMagick's convert with sixel support). The converted Sixel data is then written
--- directly to the terminal via virtual text placeholders.
local placement = require("nimbook.graphics.placement")
local graphics = require("nimbook.graphics")

local M = {}

--- Check if a Sixel converter is available
---@return string|nil converter_cmd
function M.find_converter()
  -- Prefer img2sixel (purpose-built, best quality)
  if vim.fn.executable("img2sixel") == 1 then
    return "img2sixel"
  end
  -- Fall back to chafa (widely available, supports Sixel output)
  if vim.fn.executable("chafa") == 1 then
    return "chafa"
  end
  return nil
end

--- Display an image using Sixel protocol
--- Since Sixel can't use Unicode placeholders like Kitty, we use a different approach:
--- We write the Sixel data to a temp file and display it via direct terminal output
--- when the cell's output area is in the viewport. Virtual text lines reserve the space.
---@param buf integer Buffer handle
---@param cell_idx integer Cell index
---@param image_data string Raw image bytes
---@param opts? { max_width?: integer, max_height?: integer }
---@return table[] virt_lines Virtual text lines (space reservers)
---@return nimbook.ImagePlacement placement_info
function M.display(buf, cell_idx, image_data, opts)
  opts = opts or {}
  local max_cols = opts.max_width or (vim.o.columns - 6)
  local max_rows = opts.max_height or 20

  local cell_w, cell_h = graphics.get_cell_size()
  local max_px_w = max_cols * cell_w
  local max_px_h = max_rows * cell_h

  -- Write raw image to temp file
  local tmpfile = placement.write_temp(image_data, "png")

  local converter = M.find_converter()
  if not converter then
    -- No converter available: return text placeholder
    os.remove(tmpfile)
    local virt_lines = {
      { { "[Image: install img2sixel or chafa for inline display]", "NimbookOutputFolded" } },
    }
    local pl = placement.create({
      buf = buf, line = 0, cell_idx = cell_idx,
      width = max_cols, height = 1,
    })
    return virt_lines, pl
  end

  -- Convert to Sixel
  local sixel_data = M._convert_to_sixel(tmpfile, converter, max_px_w, max_px_h)

  -- Calculate how many terminal rows the image occupies
  -- Sixel images are measured in 6-pixel-high bands
  local display_rows = M._estimate_rows(tmpfile, max_px_w, max_px_h, cell_h)

  local pl = placement.create({
    buf = buf,
    line = 0,
    cell_idx = cell_idx,
    width = max_cols,
    height = display_rows,
    tmpfile = tmpfile,
  })

  -- For Sixel, we store the converted data and render it when in viewport
  pl._sixel_data = sixel_data

  -- Build placeholder virtual lines (reserve vertical space)
  local virt_lines = {}
  for _ = 1, display_rows do
    virt_lines[#virt_lines + 1] = {
      { string.rep(" ", max_cols), "NimbookImage" },
    }
  end

  -- Write Sixel data directly to terminal
  -- Note: This is a simple approach. Sixel images don't scroll with the buffer
  -- like Kitty placeholders do. For a production-quality implementation,
  -- we'd need to track viewport changes and re-render. For now, we render
  -- once and let the placeholder lines maintain spacing.
  if sixel_data and #sixel_data > 0 then
    local wrapped = graphics.tmux_wrap(sixel_data)
    io.stdout:write(wrapped)
    io.stdout:flush()
    placement.show(pl.id)
  end

  return virt_lines, pl
end

--- Convert an image file to Sixel format
---@param filepath string Input image path
---@param converter string Converter command name
---@param max_w integer Max width in pixels
---@param max_h integer Max height in pixels
---@return string|nil sixel_data
function M._convert_to_sixel(filepath, converter, max_w, max_h)
  local cmd
  if converter == "img2sixel" then
    cmd = string.format(
      "img2sixel -w %d -h %d %s 2>/dev/null",
      max_w, max_h,
      vim.fn.shellescape(filepath)
    )
  elseif converter == "chafa" then
    cmd = string.format(
      "chafa -f sixel --size %dx%d %s 2>/dev/null",
      math.floor(max_w / 8), math.floor(max_h / 16), -- chafa uses cell dimensions
      vim.fn.shellescape(filepath)
    )
  else
    return nil
  end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return result
end

--- Estimate how many terminal rows an image will occupy
---@param filepath string
---@param max_w integer Max width in pixels
---@param max_h integer Max height in pixels
---@param cell_h integer Cell height in pixels
---@return integer rows
function M._estimate_rows(filepath, max_w, max_h, cell_h)
  -- Try to get actual image dimensions
  local kitty = require("nimbook.graphics.kitty")
  local img_w, img_h = kitty._get_image_size(filepath)

  if img_w and img_h then
    -- Scale to fit within max dimensions
    local scale = math.min(max_w / img_w, max_h / img_h, 1)
    local display_h = img_h * scale
    return math.max(1, math.ceil(display_h / cell_h))
  end

  -- Default estimate
  return math.min(10, math.floor(max_h / cell_h))
end

--- Clear a Sixel image (Sixel doesn't have a native delete command;
--- the space is just reclaimed when overwritten)
---@param pl nimbook.ImagePlacement
function M.clear(pl)
  -- Sixel images are raster; they get overwritten by terminal redraws
  -- We just clean up the temp file
  if pl.tmpfile then
    os.remove(pl.tmpfile)
  end
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

return M
