local M = {}

function M.check()
  vim.health.start("nimbook")

  -- Check Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10.0")
  else
    vim.health.error("Neovim >= 0.10.0 required", { "Upgrade Neovim to 0.10 or later" })
  end

  -- Check for treesitter markdown parser
  local ok_md = pcall(vim.treesitter.language.inspect, "markdown")
  if ok_md then
    vim.health.ok("Treesitter markdown parser installed")
  else
    vim.health.warn("Treesitter markdown parser not found", {
      "Install with :TSInstall markdown markdown_inline",
    })
  end

  -- Check for treesitter python parser
  local ok_py = pcall(vim.treesitter.language.inspect, "python")
  if ok_py then
    vim.health.ok("Treesitter python parser installed")
  else
    vim.health.warn("Treesitter python parser not found", {
      "Install with :TSInstall python",
    })
  end

  -- Check for libzmq (needed for Phase 2)
  local ffi_ok, ffi = pcall(require, "ffi")
  if ffi_ok then
    local zmq_ok = pcall(ffi.load, "zmq")
    if zmq_ok then
      vim.health.ok("libzmq found (kernel communication ready)")
    else
      vim.health.info("libzmq not found (needed for kernel execution)", {
        "Install: apt install libzmq5 / brew install zmq",
      })
    end
  end

  -- Check for ipykernel
  local ipy_result = vim.fn.system("python3 -c 'import ipykernel; print(ipykernel.__version__)'")
  if vim.v.shell_error == 0 then
    vim.health.ok("ipykernel " .. vim.trim(ipy_result))
  else
    vim.health.info("ipykernel not found (needed for kernel execution)", {
      "Install: pip install ipykernel",
    })
  end

  -- Check terminal graphics support
  local gfx = require("nimbook.graphics")
  local backend = gfx.detect()
  if backend == "kitty" then
    vim.health.ok("Graphics: Kitty protocol (inline images supported)")
  elseif backend == "sixel" then
    vim.health.ok("Graphics: Sixel protocol (inline images supported)")
    -- Check for Sixel converter
    local sixel = require("nimbook.graphics.sixel")
    local converter = sixel.find_converter()
    if converter then
      vim.health.ok("Sixel converter: " .. converter)
    else
      vim.health.warn("No Sixel converter found", {
        "Install img2sixel (apt install libsixel-bin) or chafa for inline images",
      })
    end
  else
    local term = vim.env.TERM_PROGRAM or "unknown"
    vim.health.info("Graphics: none (" .. term .. ")", {
      "For inline images, use Kitty, Ghostty, or WezTerm",
    })
  end

  -- Check for ImageMagick identify (optional, for image sizing)
  if vim.fn.executable("identify") == 1 then
    vim.health.ok("ImageMagick identify available (accurate image sizing)")
  else
    vim.health.info("ImageMagick not found (install for better image sizing)", {
      "Install: apt install imagemagick / brew install imagemagick",
    })
  end
end

return M
