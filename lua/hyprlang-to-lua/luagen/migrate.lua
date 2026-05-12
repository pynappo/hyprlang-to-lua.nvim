---A module that contains functions to convert options from pre-Lua to post-Lua.
---Organized into a separate module to help document what changes were made.
---As a note for readers doing manual conversion, the migrations documented here do not include:
---* options/keys whose camelCase or kebab-case keys have been turned into snake_case.
---* options/keys whose camelCase or kebab-case keys have been turned into snake_case.

local utils = require("hyprlang-to-lua.utils")

local migrate = {}

---@param rule HL.WindowRuleSpec
migrate.window_rule = function(rule)
  local match = rule.match
  if type(match) == "string" then
    rule.match = { class = match }
  end

  local idle_inhibit = rule.idle_inhibit
  if type(idle_inhibit) == "boolean" then
    ---types aren't complete
    ---@diagnostic disable-next-line: inject-field
    rule.idle_inhibit = idle_inhibit and "always" or "none"
  end

  ---@diagnostic disable-next-line: inject-field
  rule.border_size = tonumber(rule.border_size)
  ---@diagnostic disable-next-line: inject-field
  rule.rounding = tonumber(rule.rounding)
end

local workspace_rule_renames = {
  gapsin = "gaps_in",
  gapsout = "gaps_out",
  bordersize = "border_size",
}

---@param rule HL.WorkspaceRuleSpec
---@param keys string[]
migrate.workspace_rule = function(rule, keys)
  utils.tbl_replace_keys(rule, workspace_rule_renames)
  utils.list_gsub(keys, workspace_rule_renames)
end

---@param key string
migrate.bind_key = function(key)
  if #key > 4 and key:upper():find("ENTER") then
    return "Return"
  end
  return key
end

--- See https://github.com/hyprwm/Hyprland/blob/5e441cae538c9396f2ee30338419bec12969608c/src/managers/KeybindManager.cpp#L220-L235
local valid_mods = {
  "SHIFT",
  "CAPS",
  "CTRL",
  "CONTROL",
  "ALT",
  "MOD1",
  "MOD2",
  "MOD3",
  "MOD4",
  "SUPER",
  "WIN",
  "LOGO",
  "META",
  "MOD5",
}

---Given a set of search words, returns a list of words in the order of their first occurence in the input.
---@param input string
---@param words string[]
---@return string[] mods
local function find_words(input, words)
  local results = {}

  for _, word in ipairs(words) do
    local pos = input:find(word, 1, true)
    if pos then
      results[#results + 1] = {
        word = word,
        pos = pos,
      }
    end
  end

  table.sort(results, function(a, b)
    return a.pos < b.pos
  end)

  local ordered = {}
  for _, item in ipairs(results) do
    table.insert(ordered, item.word)
  end
  return ordered
end

---Mods and keys are combined into one +-delimited string
---@param modstring string
---@param key string
---@return string lhs
migrate.bind_mod_and_keys_to_lhs = function(modstring, key)
  modstring = modstring:upper()
  local mods = find_words(modstring, valid_mods)
  if key:upper():find("ENTER", 1, true) then
    key = "Return"
  end
  return table.concat(vim.list_extend(mods, { key }), " + ")
end

return migrate
