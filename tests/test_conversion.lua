local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local hyprtolua = require("hyprlang-to-lua")
local utils = require("tests.utils")
local T = new_set()

---@param filename string
---@return string[]
local readlines = function(filename)
  local lines = {}
  for line in io.lines(filename) do
    lines[#lines + 1] = line
  end
  return lines
end
T["works"] = function()
  local localconf_lines = readlines("testdata/local.conf")
  local localconf_str = table.concat(localconf_lines, "\n")
  local converted = hyprtolua.convert(localconf_str)
  utils.expect_lines_match({
    [[
hl.monitor({
  output = "DP-3",
  mode = "2560x1440@170",
  position = "-2560x0",
  scale = "1",
  vrr = 3,
})]],
    [[
hl.monitor({
	output = "DP-2",
	mode = "highrr",
	position = "0x0",
	scale = "1.5",
	vrr = 1,
})]],
    [[hl.env("PROTON_WAYLAND_MONITOR", "DP-2")]],
    [[hl.workspace_rule({ workspace = "1", monitor = "DP-3" })]],
    [[hl.workspace_rule({ workspace = "2", monitor = "DP-2" })]],
    [[hl.workspace_rule({ workspace = "3", monitor = "DP-3" })]],
    [[hl.workspace_rule({ workspace = "4", monitor = "DP-2" })]],
    [[hl.workspace_rule({ workspace = "5", monitor = "DP-3" })]],
    [[hl.workspace_rule({ workspace = "6", monitor = "DP-2" })]],
    [[hl.workspace_rule({ workspace = "7", monitor = "DP-3" })]],
    [[hl.workspace_rule({ workspace = "8", monitor = "DP-2" })]],
    [[hl.workspace_rule({ workspace = "9", monitor = "DP-3" })]],
    [[hl.workspace_rule({ workspace = "10", monitor = "DP-2" })]],
  }, converted)
end

return T
