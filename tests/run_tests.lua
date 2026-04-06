--- Simple test runner that doesn't depend on external test frameworks.
--- Usage: nvim --headless -u tests/minimal_init.lua -l tests/run_tests.lua

local passed = 0
local failed = 0
local errors = {}

local current_describe = ""

function describe(name, fn)
  current_describe = name
  fn()
  current_describe = ""
end

function it(name, fn)
  local full_name = current_describe .. " > " .. name
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write("  \27[32m✓\27[0m " .. full_name .. "\n")
  else
    failed = failed + 1
    errors[#errors + 1] = { name = full_name, err = err }
    io.write("  \27[31m✖\27[0m " .. full_name .. "\n")
    io.write("    " .. tostring(err) .. "\n")
  end
end

-- Simple assertion library that preserves the original assert() function
local _assert = assert
assert = setmetatable({}, {
  __call = function(_, ...)
    return _assert(...)
  end,
  __index = function(_, key)
    if key == "equals" then
      return function(expected, actual)
        if expected ~= actual then
          error(string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)), 2)
        end
      end
    elseif key == "is_not_nil" then
      return function(val)
        if val == nil then
          error("expected non-nil value", 2)
        end
      end
    elseif key == "is_nil" then
      return function(val)
        if val ~= nil then
          error(string.format("expected nil, got %s", vim.inspect(val)), 2)
        end
      end
    elseif key == "is_true" then
      return function(val)
        if not val then
          error("expected true", 2)
        end
      end
    elseif key == "same" then
      return function(expected, actual)
        if vim.inspect(expected) ~= vim.inspect(actual) then
          error(string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)), 2)
        end
      end
    end
  end,
})

-- Run test files
io.write("\n\27[1mnimbook tests\27[0m\n\n")

dofile("tests/nimbook/notebook_spec.lua")
dofile("tests/nimbook/wire_spec.lua")
dofile("tests/nimbook/render_spec.lua")
dofile("tests/nimbook/export_spec.lua")

io.write(string.format("\n\27[1mResults: %d passed, %d failed\27[0m\n\n", passed, failed))

if failed > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("quit")
end
