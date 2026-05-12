---A module that to help organize functions that convert options from pre-Lua to post-Lua
local normalize = {}

---@param opts HL.WindowRuleSpec
normalize.window_rule_inplace = function(opts)
  local match = opts.match
  if type(match) == "string" then
    opts.match = { class = match }
  end
end

return normalize
