--- Buffer-to-notebook state registry
--- vim.b[] can't store complex Lua tables, so we use a module-level map.
local M = {}

---@type table<integer, nimbook.Notebook>
local notebooks = {}

---@type table<integer, nimbook.KernelManager>
local kernels = {}

---@param buf integer
---@param notebook nimbook.Notebook
function M.set(buf, notebook)
  notebooks[buf] = notebook
end

---@param buf integer
---@return nimbook.Notebook|nil
function M.get(buf)
  return notebooks[buf]
end

---@param buf integer
---@param kernel nimbook.KernelManager
function M.set_kernel(buf, kernel)
  kernels[buf] = kernel
end

---@param buf integer
---@return nimbook.KernelManager|nil
function M.get_kernel(buf)
  return kernels[buf]
end

---@param buf integer
function M.remove(buf)
  local km = kernels[buf]
  if km then
    km:_cleanup()
  end
  kernels[buf] = nil
  notebooks[buf] = nil
end

return M
