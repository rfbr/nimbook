local M = {}

function M.setup()
  local hl = vim.api.nvim_set_hl

  -- Cell borders
  hl(0, "NimbookBorder", { link = "FloatBorder" })
  hl(0, "NimbookBorderCode", { link = "FloatBorder" })
  hl(0, "NimbookBorderMarkdown", { link = "FloatBorder" })

  -- Cell header labels
  hl(0, "NimbookCellType", { link = "Type" })
  hl(0, "NimbookCellLanguage", { link = "Keyword" })
  hl(0, "NimbookCellCount", { link = "Number" })
  hl(0, "NimbookCellTime", { link = "Comment" })

  -- Execution status icons
  hl(0, "NimbookStatusIdle", { link = "Comment" })
  hl(0, "NimbookStatusRunning", { link = "DiagnosticWarn" })
  hl(0, "NimbookStatusDone", { link = "DiagnosticOk" })
  hl(0, "NimbookStatusError", { link = "DiagnosticError" })
  hl(0, "NimbookStatusQueued", { link = "DiagnosticInfo" })

  -- Output rendering
  hl(0, "NimbookOutput", { link = "Normal" })
  hl(0, "NimbookOutputStdout", { link = "String" })
  hl(0, "NimbookOutputStderr", { link = "DiagnosticError" })
  hl(0, "NimbookOutputResult", { link = "Special" })
  hl(0, "NimbookOutputError", { link = "ErrorMsg" })
  hl(0, "NimbookOutputBorder", { link = "FloatBorder" })
  hl(0, "NimbookOutputFolded", { link = "Comment" })

  -- Cell content background (subtle differentiation)
  hl(0, "NimbookCodeCell", { default = true })
  hl(0, "NimbookMarkdownCell", { default = true })

  -- Fence concealment (make fence lines near-invisible)
  hl(0, "NimbookFenceHidden", { fg = "bg", bg = "bg" })

  -- Image placeholder (transparent/invisible for Kitty placeholders)
  hl(0, "NimbookImage", { default = true })

  -- ANSI color highlights
  require("nimbook.util.ansi").setup_highlights()
end

return M
