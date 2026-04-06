--- Image placement lifecycle management
--- Tracks active image placements, handles cleanup on scroll/buffer changes,
--- and manages temporary files.
local M = {}

---@class nimbook.ImagePlacement
---@field id integer Unique placement ID
---@field image_id integer Kitty image ID (or 0 for Sixel)
---@field buf integer Buffer handle
---@field line integer Buffer line (0-indexed) where the image is anchored
---@field cell_idx integer Notebook cell index that owns this image
---@field width integer Image width in terminal columns
---@field height integer Image height in terminal rows
---@field tmpfile string|nil Path to temp file (for Kitty file-based transfer)
---@field visible boolean Whether the image is currently rendered

---@type table<integer, nimbook.ImagePlacement>
local placements = {}

local next_id = 1
local next_image_id = 1

--- Register a new image placement
---@param opts { buf: integer, line: integer, cell_idx: integer, width: integer, height: integer, tmpfile?: string }
---@return nimbook.ImagePlacement
function M.create(opts)
  local placement = {
    id = next_id,
    image_id = next_image_id,
    buf = opts.buf,
    line = opts.line,
    cell_idx = opts.cell_idx,
    width = opts.width,
    height = opts.height,
    tmpfile = opts.tmpfile,
    visible = false,
  }
  placements[next_id] = placement
  next_id = next_id + 1
  next_image_id = next_image_id + 1
  return placement
end

--- Mark a placement as visible (image has been rendered)
---@param id integer
function M.show(id)
  if placements[id] then
    placements[id].visible = true
  end
end

--- Remove a specific placement and clean up its temp file
---@param id integer
---@param clear_fn? fun(placement: nimbook.ImagePlacement) Function to send clear command to terminal
function M.remove(id, clear_fn)
  local placement = placements[id]
  if not placement then
    return
  end
  if placement.visible and clear_fn then
    clear_fn(placement)
  end
  if placement.tmpfile then
    os.remove(placement.tmpfile)
  end
  placements[id] = nil
end

--- Remove all placements for a specific buffer
---@param buf integer
---@param clear_fn? fun(placement: nimbook.ImagePlacement)
function M.remove_for_buffer(buf, clear_fn)
  local to_remove = {}
  for id, placement in pairs(placements) do
    if placement.buf == buf then
      to_remove[#to_remove + 1] = id
    end
  end
  for _, id in ipairs(to_remove) do
    M.remove(id, clear_fn)
  end
end

--- Remove all placements for a specific cell in a buffer
---@param buf integer
---@param cell_idx integer
---@param clear_fn? fun(placement: nimbook.ImagePlacement)
function M.remove_for_cell(buf, cell_idx, clear_fn)
  local to_remove = {}
  for id, placement in pairs(placements) do
    if placement.buf == buf and placement.cell_idx == cell_idx then
      to_remove[#to_remove + 1] = id
    end
  end
  for _, id in ipairs(to_remove) do
    M.remove(id, clear_fn)
  end
end

--- Get all placements for a buffer
---@param buf integer
---@return nimbook.ImagePlacement[]
function M.get_for_buffer(buf)
  local result = {}
  for _, placement in pairs(placements) do
    if placement.buf == buf then
      result[#result + 1] = placement
    end
  end
  return result
end

--- Check which placements are in the visible viewport and which are not
---@param buf integer
---@param top_line integer Top visible line (0-indexed)
---@param bot_line integer Bottom visible line (0-indexed)
---@return nimbook.ImagePlacement[] visible, nimbook.ImagePlacement[] offscreen
function M.partition_by_viewport(buf, top_line, bot_line)
  local visible = {}
  local offscreen = {}
  for _, placement in pairs(placements) do
    if placement.buf == buf then
      if placement.line >= top_line and placement.line <= bot_line then
        visible[#visible + 1] = placement
      else
        offscreen[#offscreen + 1] = placement
      end
    end
  end
  return visible, offscreen
end

--- Clean up all placements (called on plugin unload)
---@param clear_fn? fun(placement: nimbook.ImagePlacement)
function M.cleanup_all(clear_fn)
  for id, _ in pairs(placements) do
    M.remove(id, clear_fn)
  end
end

--- Create a temp file and write data to it
---@param data string Binary image data
---@param ext? string File extension (default: "png")
---@return string path
function M.write_temp(data, ext)
  ext = ext or "png"
  local path = vim.fn.tempname() .. "." .. ext
  local f = io.open(path, "wb")
  if not f then
    error("nimbook: failed to create temp file: " .. path)
  end
  f:write(data)
  f:close()
  return path
end

return M
