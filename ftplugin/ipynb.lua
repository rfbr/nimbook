local Notebook = require("nimbook.notebook")
local renderer = require("nimbook.render")
local buf_sync = require("nimbook.render.buffer")
local config = require("nimbook.config")

local buf = vim.api.nvim_get_current_buf()

-- State: store notebook per buffer
if not vim.b[buf].nimbook then
  -- Read the .ipynb file
  local filepath = vim.api.nvim_buf_get_name(buf)
  local notebook

  if filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
    local f = io.open(filepath, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, nb = pcall(Notebook.parse, content, filepath)
      if ok then
        notebook = nb
      else
        vim.notify("nimbook: failed to parse " .. filepath .. ": " .. tostring(nb), vim.log.levels.ERROR)
        return
      end
    end
  end

  if not notebook then
    notebook = Notebook.empty(filepath)
  end

  -- Store notebook reference on the buffer
  vim.b[buf].nimbook = true
  -- We use a module-level registry since vim.b can't store complex Lua objects
  require("nimbook.state").set(buf, notebook)

  -- Buffer settings
  vim.bo[buf].filetype = "ipynb"
  vim.bo[buf].syntax = "markdown"
  vim.bo[buf].buftype = ""
  vim.bo[buf].swapfile = false

  -- Enable treesitter markdown if available
  local ok_ts = pcall(vim.treesitter.start, buf, "markdown")
  if not ok_ts then
    -- Fallback: just use syntax highlighting
    vim.bo[buf].syntax = "markdown"
  end

  -- Render the notebook
  renderer.render(buf, notebook)

  -- Mark as not modified after initial render
  vim.bo[buf].modified = false

  -- Set up BufWriteCmd for custom save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local nb = require("nimbook.state").get(buf)
      if not nb then
        return
      end
      -- Sync buffer content back to notebook data model
      buf_sync.sync_from_buffer(nb, buf)
      -- Write to disk
      local fp = vim.api.nvim_buf_get_name(buf)
      local write_ok, err = pcall(nb.write, nb, fp)
      if write_ok then
        vim.bo[buf].modified = false
        vim.notify("nimbook: saved " .. vim.fn.fnamemodify(fp, ":t"), vim.log.levels.INFO)
      else
        vim.notify("nimbook: save failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })

  -- Redecorate on window resize
  vim.api.nvim_create_autocmd("WinResized", {
    buffer = buf,
    callback = function()
      local nb = require("nimbook.state").get(buf)
      if nb then
        renderer.redecorate(buf, nb)
      end
    end,
  })

  -- Recompute mappings on text change (debounced)
  local timer = vim.uv.new_timer()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      timer:stop()
      timer:start(100, 0, vim.schedule_wrap(function()
        local nb = require("nimbook.state").get(buf)
        if nb and vim.api.nvim_buf_is_valid(buf) then
          buf_sync.recompute_mappings(nb, buf)
          renderer.redecorate(buf, nb)
        end
      end))
    end,
  })

  -- Lazy rendering: redecorate on scroll (debounced)
  local scroll_timer = vim.uv.new_timer()
  vim.api.nvim_create_autocmd("WinScrolled", {
    buffer = buf,
    callback = function()
      scroll_timer:stop()
      scroll_timer:start(50, 0, vim.schedule_wrap(function()
        local nb = require("nimbook.state").get(buf)
        if nb and vim.api.nvim_buf_is_valid(buf) then
          renderer.redecorate(buf, nb)
        end
      end))
    end,
  })

  -- Set up folding
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "v:lua.require'nimbook.fold'.foldexpr()"
  vim.wo.foldtext = "v:lua.require'nimbook.fold'.foldtext()"
  vim.wo.foldlevel = 99 -- start with all cells unfolded
  vim.wo.foldenable = true

  -- Register nvim-cmp source if available
  pcall(require("nimbook.completion").register)

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      timer:stop()
      timer:close()
      scroll_timer:stop()
      scroll_timer:close()
      require("nimbook.state").remove(buf)
    end,
  })

  -- Set up keymaps
  local km = config.current.keymaps
  local ops = "nimbook.operations"
  local map_opts = { buffer = buf, silent = true }

  local keymaps = {
    { km.cell_next, ops, "goto_next_cell", "Next cell" },
    { km.cell_prev, ops, "goto_prev_cell", "Previous cell" },
    { km.cell_next_code, ops, "goto_next_code_cell", "Next code cell" },
    { km.cell_prev_code, ops, "goto_prev_code_cell", "Previous code cell" },
    { km.cell_add_below, ops, "add_cell_below", "Add cell below" },
    { km.cell_add_above, ops, "add_cell_above", "Add cell above" },
    { km.cell_delete, ops, "delete_cell", "Delete cell" },
    { km.cell_type, ops, "toggle_cell_type", "Toggle cell type" },
    { km.cell_move_down, ops, "move_cell_down", "Move cell down" },
    { km.cell_move_up, ops, "move_cell_up", "Move cell up" },
    { km.output_toggle, ops, "toggle_output", "Toggle output" },
    { km.output_toggle_all, ops, "toggle_all_outputs", "Toggle all outputs" },
    { km.output_clear, ops, "clear_output", "Clear output" },
    { km.output_clear_all, ops, "clear_all_outputs", "Clear all outputs" },
    { km.output_expand, ops, "output_expand", "Expand output" },
    { km.kernel_start, ops, "kernel_start", "Start kernel" },
    { km.kernel_restart, ops, "kernel_restart", "Restart kernel" },
    { km.kernel_interrupt, ops, "kernel_interrupt", "Interrupt kernel" },
    { km.execute, ops, "execute_cell", "Execute cell" },
    { km.execute_and_advance, ops, "execute_and_advance", "Execute and advance" },
    { km.execute_all, ops, "execute_all", "Execute all" },
  }

  for _, km_def in ipairs(keymaps) do
    local lhs, mod, fn_name, desc = km_def[1], km_def[2], km_def[3], km_def[4]
    vim.keymap.set("n", lhs, function()
      require(mod)[fn_name]()
    end, vim.tbl_extend("force", map_opts, { desc = "Nimbook: " .. desc }))
  end

  -- Hover / inspect keymap (K is conventional for documentation)
  vim.keymap.set("n", "K", function()
    -- Only use nimbook hover if kernel is connected, otherwise fall back
    local km_state = require("nimbook.state").get_kernel(buf)
    if km_state and km_state.status ~= "disconnected" then
      require("nimbook.inspect").hover()
    else
      vim.lsp.buf.hover()
    end
  end, vim.tbl_extend("force", map_opts, { desc = "Nimbook: Hover docs" }))

  -- Cell text objects (ic / ac)
  require("nimbook.textobjects").setup(buf)
end
