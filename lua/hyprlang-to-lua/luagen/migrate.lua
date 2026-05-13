---A module that contains functions to convert options from pre-Lua to post-Lua.
---Organized into a separate module to help document what changes were made.
---As a note for readers doing manual conversion, the migrations documented here do not include:
---* options/keys whose camelCase or kebab-case keys have been turned into snake_case.

local utils = require("hyprlang-to-lua.utils")
local pretty = require("hyprlang-to-lua.luagen.pretty")
local luagen_utils = require("hyprlang-to-lua.luagen.utils")

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

  ---@diagnostic disable-next-line: undefined-field
  local workspace = rule.workspace
  if type(workspace) == "table" then
    return table.concat(workspace, " ")
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

---@param modstring string
---@return string[]
migrate.find_mods = function(modstring)
  return find_words(modstring:upper(), valid_mods)
end

---Mods and keys are combined into one +-delimited string.
---Also returns variable names that are in the mod string.
---@param modstring string
---@param bind_key string
---@return string lhs_code
migrate.bind_lhs_code = function(modstring, bind_key)
  ---@type (hyprtolua.VariableToken|string)[]
  local keys = {}
  for _, token in ipairs(luagen_utils.totokens(modstring)) do
    if type(token) == "string" then
      vim.list_extend(keys, migrate.find_mods(token))
    else
      ---Assume that each variable is just a variable for a key
      keys[#keys + 1] = token
    end
  end

  if bind_key:upper():find("ENTER", 1, true) then
    bind_key = "Return"
  end

  keys[#keys + 1] = bind_key
  local luacode_exprs = {}
  local string_parts = {}
  ---@type type?
  local prev_keytype = nil
  for _, k in ipairs(keys) do
    local keytype = type(k)
    if keytype == "table" then
      -- "MOD +" .. var
      if prev_keytype == "string" then
        string_parts[#string_parts + 1] = " + "
        -- commit the string
        luacode_exprs[#luacode_exprs + 1] = pretty.toluacode(table.concat(string_parts))
        string_parts = {}
      else
        if prev_keytype == "table" then
          -- var1 .. " + " .. var2
          luacode_exprs[#luacode_exprs + 1] = pretty.toluacode(" + ")
        end
        luacode_exprs[#luacode_exprs + 1] = k.varname
      end
    elseif keytype == "string" then
      -- simply add onto the string builder
      if prev_keytype then
        string_parts[#string_parts + 1] = " + "
      end
      string_parts[#string_parts + 1] = k
    end
    prev_keytype = keytype
  end

  if #string_parts > 0 then
    luacode_exprs[#luacode_exprs + 1] = pretty.toluacode(table.concat(string_parts))
  end
  return table.concat(luacode_exprs, " .. ")
end

---An opinionated variable name formatter which converts hyprlang $variables to lua-compatible snake_case (unless it was all-caps)
---@param varname string
---@return string new_varname
---@nodiscard
migrate.variable_name = function(varname)
  if vim.startswith(varname, "$") then
    varname = varname:sub(2)
  end

  local varname_snake_case = utils.tosnakecase(varname)
  if varname == varname:upper() then
    return varname_snake_case:upper()
  end
  return varname_snake_case
end

return migrate
