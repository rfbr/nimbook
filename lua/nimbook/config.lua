local M = {}

---@class nimbook.Config
---@field keymaps nimbook.KeymapConfig
---@field render nimbook.RenderConfig
---@field kernel nimbook.KernelConfig

---@class nimbook.KeymapConfig
---@field execute string
---@field execute_and_advance string
---@field execute_all string
---@field cell_next string
---@field cell_prev string
---@field cell_next_code string
---@field cell_prev_code string
---@field cell_add_below string
---@field cell_add_above string
---@field cell_delete string
---@field cell_type string
---@field cell_move_down string
---@field cell_move_up string
---@field output_toggle string
---@field output_toggle_all string
---@field output_clear string
---@field output_clear_all string
---@field output_expand string
---@field kernel_start string
---@field kernel_restart string
---@field kernel_interrupt string

---@class nimbook.RenderConfig
---@field output_max_lines integer Max visible output lines before folding
---@field show_execution_count boolean
---@field show_execution_time boolean
---@field border_style "rounded"|"sharp"|"double"

---@class nimbook.KernelConfig
---@field python_cmd string Python command to use for ipykernel

---@type nimbook.Config
M.defaults = {
  keymaps = {
    execute = "<C-CR>",
    execute_and_advance = "<S-CR>",
    execute_all = "<M-CR>",
    cell_next = "]c",
    cell_prev = "[c",
    cell_next_code = "]C",
    cell_prev_code = "[C",
    cell_add_below = "<leader>na",
    cell_add_above = "<leader>nA",
    cell_delete = "<leader>nd",
    cell_type = "<leader>nt",
    cell_move_down = "<leader>nj",
    cell_move_up = "<leader>nk",
    output_toggle = "<leader>no",
    output_toggle_all = "<leader>nO",
    output_clear = "<leader>nx",
    output_clear_all = "<leader>nX",
    output_expand = "<leader>ne",
    play_media = "<leader>np",
    kernel_start = "<leader>ns",
    kernel_restart = "<leader>nr",
    kernel_interrupt = "<leader>ni",
  },
  render = {
    output_max_lines = 15,
    show_execution_count = true,
    show_execution_time = true,
    border_style = "rounded",
  },
  kernel = {
    python_cmd = "python3",
  },
}

---@type nimbook.Config
M.current = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

--- Get border characters for the configured style
---@return table
function M.border_chars()
  local styles = {
    rounded = {
      top_left = "╭",
      top_right = "╮",
      bottom_left = "╰",
      bottom_right = "╯",
      horizontal = "─",
      vertical = "│",
      tee_right = "├",
      tee_left = "┤",
    },
    sharp = {
      top_left = "┌",
      top_right = "┐",
      bottom_left = "└",
      bottom_right = "┘",
      horizontal = "─",
      vertical = "│",
      tee_right = "├",
      tee_left = "┤",
    },
    double = {
      top_left = "╔",
      top_right = "╗",
      bottom_left = "╚",
      bottom_right = "╝",
      horizontal = "═",
      vertical = "║",
      tee_right = "╠",
      tee_left = "╣",
    },
  }
  return styles[M.current.render.border_style] or styles.rounded
end

return M
