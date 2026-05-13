local M = {}

---@class hyprtolua.Tokens
---@field [integer] hyprtolua.VariableToken|string

---@class hyprtolua.VariableToken
---@field varname string
---@field original_varname string

---@type hyprtolua.Internal.Metatable
local tokens_mt = {
  ---@param tbl hyprtolua.Tokens
  __toluacode = function(tbl)
    local code_parts = {}
    for i, part in ipairs(tbl) do
      local parttype = type(part)
      code_parts[i] = parttype == "string"
          and require("hyprlang-to-lua.luagen.pretty").toluacode(part)
        or part.varname
    end
    return table.concat(code_parts, " .. ")
  end,
}

---@type hyprtolua.Internal.Metatable
local token_mt = {
  ---@param tbl hyprtolua.VariableToken
  __toluacode = function(tbl)
    return tbl.varname
  end,
}

---Tokens are a structure that represents a hyprlang string and its composite literals and variables. __toluacode() is
---implemented on them so they properly evaluate to a string concatenation expression.
---@param str string
---@return hyprtolua.Tokens
M.totokens = function(str)
  local parts = {
    raw = str,
  }
  local last_pos = 1

  for pos, var_name in str:gmatch("()%$([%a][%w]*)") do
    if pos > last_pos then
      parts[#parts + 1] = str:sub(last_pos, pos - 1)
    end
    ---@type hyprtolua.VariableToken
    local token = {
      original_varname = var_name,
      varname = require("hyprlang-to-lua.luagen.migrate").variable_name(var_name),
    }
    setmetatable(token, token_mt)
    parts[#parts + 1] = token
    last_pos = pos + #var_name + 1
  end

  if last_pos <= #str then
    parts[#parts + 1] = str:sub(last_pos)
  end

  setmetatable(parts, tokens_mt)
  return parts
end

---@type hyprtolua.Internal.Metatable
---@return table
local rawluacode_mt = {
  ---@param self hyprtolua.Internal.RawLuaCodeWrapper
  __toluacode = function(self)
    return self
  end,
}
M.wrap_raw_luacode = function(str)
  ---@class hyprtolua.Internal.RawLuaCodeWrapper
  local wrapper = { rawluacode = str }
  setmetatable(str, rawluacode_mt)
  return wrapper
end

return M
