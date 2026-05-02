local parser = require("hyprlang-to-lua.ir_parser")
local M = {}

---@param hyprlang_text string
function M.convert(hyprlang_text)
	local hyprlang_parser = vim.treesitter.get_string_parser(hyprlang_text, "hyprlang")
	local tree = hyprlang_parser:parse(true)
	if not tree or not tree[1] then
		error("Failed to parse hyprlang text:\n" .. hyprlang_text)
	end
	local configuration_root = tree[1]:root() -- configuration
	return parser.parse_configuration(configuration_root, hyprlang_text)
end

return M
