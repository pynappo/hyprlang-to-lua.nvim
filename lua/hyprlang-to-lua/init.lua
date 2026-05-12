local ir_parser = require("hyprlang-to-lua.ir_parser")
local luagen = require("hyprlang-to-lua.luagen")
local utils = require("hyprlang-to-lua.utils")
local optimize = require("hyprlang-to-lua.luagen.optimize")
local M = {}

---@param hyprlang_text string
---@return string[] lua_lines
---@return hyprtolua.ir.Configuration config_ir_for_debug
M.convert = function(hyprlang_text)
  local hyprlang_parser = vim.treesitter.get_string_parser(hyprlang_text, "hyprlang")
  local tree = hyprlang_parser:parse(true)
  if not tree or not tree[1] then
    error("Failed to parse hyprlang text:\n" .. hyprlang_text)
  end
  local configuration_root = tree[1]:root() -- configuration
  local config_ir = ir_parser.parse_configuration(configuration_root, hyprlang_text)
  local chunks = luagen.config_toluacode(config_ir)
  chunks = optimize.optimize(chunks)
  local date = os.date("%Y-%m-%dT%H:%M:%S")

  local lines = {
    ("-- Start of translated config by hyprlang-to-lua.nvim on %s"):format(date),
  }
  for _, chunk in ipairs(chunks) do
    for line in vim.gsplit(chunk, "\n", { plain = true }) do
      lines[#lines + 1] = line
    end
  end
  lines[#lines + 1] = ("-- End of translated config by hyprlang-to-lua.nvim on %s"):format(date)
  return lines, config_ir
end

---@param path string
M.convert_to_stdout_then_quit = function(path)
  local text = utils.readfile(path)
  local lua_lines = table.concat(M.convert(text), "\n")
  io.stdout:write(lua_lines)
  vim.cmd.quit()
end

return M
