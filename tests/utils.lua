local M = {}
local ANSI_CODES = {
  RED = "\27[31m",
  RESET = "\27[0m",
}
local red = function(str)
  return ("%s%s%s"):format(ANSI_CODES.RED, str, ANSI_CODES.RESET)
end
---@param a string[]
---@param b string[]
M.expect_lines_match = MiniTest.new_expectation("line matching (with better debug)", function(a, b)
  local all_matched = true
  if #a ~= #b then
    return false
  end
  for i, line in ipairs(a) do
    if b[i] ~= line then
      all_matched = false
    end
  end
  return all_matched
end, function(expected, actual)
  local mismatches = {}
  for i = 1, math.max(#expected, #actual) do
    local expected_line = expected[i]
    local actual_line = actual[i]
    if expected_line ~= actual_line then
      mismatches[#mismatches + 1] = ([[%s
%s
%s
%s
%s"]]):format(
        red(("[Mismatch %s]"):format(i)),
        red("Expected:"),
        expected_line,
        red("Actual:"),
        actual_line
      )
    end
  end
  return ([[
Lines from actual did not match expected:
%s
]]):format(table.concat(mismatches, "\n"))
end)

---@type fun(hyprlang: string, lua: string)
M.expect_hyprtolua_line = MiniTest.new_expectation(
  "hyprlang to lua conversion",
  ---@param hyprlang string
  ---@param lua string
  function(hyprlang, lua)
    local converted = require("hyprlang-to-lua").convert(hyprlang, true)
    return converted[1] == lua
  end,
  ---@param hyprlang string
  ---@param lua string
  function(hyprlang, lua)
    local converted = require("hyprlang-to-lua").convert(hyprlang, true)
    local converted_hyprlang = converted[1]
    return ([[Expected hyprlang line:
%s
to convert into:
%s
got:
%s
]]):format(hyprlang, lua, converted_hyprlang)
  end
)

return M
