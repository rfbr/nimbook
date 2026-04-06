if vim.g.loaded_nimbook then
  return
end
vim.g.loaded_nimbook = true

-- Register .ipynb filetype
vim.filetype.add({
  extension = {
    ipynb = "ipynb",
  },
})

-- Commands
local function create_commands()
  local cmd = vim.api.nvim_create_user_command

  -- Cell operations
  cmd("NimbookCellAdd", function()
    require("nimbook.operations").add_cell_below()
  end, { desc = "Add a new code cell below current" })

  cmd("NimbookCellAddAbove", function()
    require("nimbook.operations").add_cell_above()
  end, { desc = "Add a new code cell above current" })

  cmd("NimbookCellDelete", function()
    require("nimbook.operations").delete_cell()
  end, { desc = "Delete current cell" })

  cmd("NimbookCellType", function()
    require("nimbook.operations").toggle_cell_type()
  end, { desc = "Toggle cell type (code/markdown)" })

  cmd("NimbookCellMoveUp", function()
    require("nimbook.operations").move_cell_up()
  end, { desc = "Move current cell up" })

  cmd("NimbookCellMoveDown", function()
    require("nimbook.operations").move_cell_down()
  end, { desc = "Move current cell down" })

  -- Output operations
  cmd("NimbookOutputToggle", function()
    require("nimbook.operations").toggle_output()
  end, { desc = "Toggle output visibility for current cell" })

  cmd("NimbookOutputToggleAll", function()
    require("nimbook.operations").toggle_all_outputs()
  end, { desc = "Toggle all output visibility" })

  cmd("NimbookOutputClear", function()
    require("nimbook.operations").clear_output()
  end, { desc = "Clear output for current cell" })

  cmd("NimbookOutputClearAll", function()
    require("nimbook.operations").clear_all_outputs()
  end, { desc = "Clear all outputs" })

  cmd("NimbookOutputExpand", function()
    require("nimbook.operations").output_expand()
  end, { desc = "Show full output in floating window" })

  -- Kernel operations
  cmd("NimbookKernelStart", function()
    require("nimbook.operations").kernel_start()
  end, { desc = "Start a new kernel" })

  cmd("NimbookKernelAttach", function()
    require("nimbook.operations").kernel_attach()
  end, { desc = "Attach to an existing kernel" })

  cmd("NimbookKernelRestart", function()
    require("nimbook.operations").kernel_restart()
  end, { desc = "Restart the kernel" })

  cmd("NimbookKernelInterrupt", function()
    require("nimbook.operations").kernel_interrupt()
  end, { desc = "Interrupt kernel execution" })

  cmd("NimbookKernelShutdown", function()
    require("nimbook.operations").kernel_shutdown()
  end, { desc = "Shutdown the kernel" })

  -- Execution
  cmd("NimbookExecute", function()
    require("nimbook.operations").execute_cell()
  end, { desc = "Execute current cell" })

  cmd("NimbookExecuteAndAdvance", function()
    require("nimbook.operations").execute_and_advance()
  end, { desc = "Execute current cell and advance" })

  cmd("NimbookExecuteAll", function()
    require("nimbook.operations").execute_all()
  end, { desc = "Execute all cells" })

  -- Inspect / Hover
  cmd("NimbookInspect", function()
    require("nimbook.inspect").hover()
  end, { desc = "Show documentation for symbol under cursor" })

  -- Export
  cmd("NimbookExport", function(opts)
    if opts.args and opts.args ~= "" then
      require("nimbook.export").export(opts.args)
    else
      require("nimbook.export").export_interactive()
    end
  end, { nargs = "?", complete = function() return { "py", "md" } end, desc = "Export notebook" })
end

create_commands()
