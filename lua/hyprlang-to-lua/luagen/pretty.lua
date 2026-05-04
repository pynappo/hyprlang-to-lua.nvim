local M = {}

---Based on StyLua opts, adjusted to the settings on the hyprland wiki.
---@class hyprtolua.FormatOpts
M.opts = {
  syntax = "All",
  column_width = 80, -- Adjusted to 80
  line_endings = "Unix",
  ---@type "Spaces"|"Tabs"
  indent_type = "Spaces", -- Spaces used on wiki
  indent_width = 4,
  quote_style = "AutoPreferDouble",
  call_parentheses = "Always",
  collapse_simple_statement = "Never",
  space_after_function_names = "Never",
  block_newline_gaps = "Never",

  -- sort_requires = false, -- not bothering with
}

---From kikito/inspect.lua
-- inspect._VERSION = 'inspect.lua 3.1.0'
-- inspect._URL = 'http://github.com/kikito/inspect.lua'
-- inspect._DESCRIPTION = 'human-readable representations of tables'
-- inspect._LICENSE = [[
--   MIT LICENSE
--
--   Copyright (c) 2022 Enrique García Cota
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the
--   "Software"), to deal in the Software without restriction, including
--   without limitation the rights to use, copy, modify, merge, publish,
--   distribute, sublicense, and/or sell copies of the Software, and to
--   permit persons to whom the Software is furnished to do so, subject to
--   the following conditions:
--
--   The above copyright notice and this permission notice shall be included
--   in all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
--   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
--   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
--   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
--   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
--   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
--   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ]]
local shortControlCharEscapes = {
  ["\a"] = "\\a",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  ["\v"] = "\\v",
  ["\127"] = "\\127",
}
local longControlCharEscapes = { ["\127"] = "\127" }
for i = 0, 31 do
  local ch = string.char(i)
  if not shortControlCharEscapes[ch] then
    shortControlCharEscapes[ch] = "\\" .. i
    longControlCharEscapes[ch] = string.format("\\%03d", i)
  end
end

---@param str string
local function escape(str)
  return str
    :gsub("\\", "\\\\")
    :gsub("(%c)%f[0-9]", longControlCharEscapes)
    :gsub("%c", shortControlCharEscapes)
end

---@param level integer
---@return string
local indent = function(level)
  if M.opts.indent_type == "Spaces" then
    return (" "):rep(M.opts.indent_width):rep(level)
  elseif M.opts.indent_type == "Tabs" then
    return ("\t"):rep(level)
  end
  error("Could not determine indent")
end

M.indent = indent

---@param str string
---@return string luastring A valid string in lua code
M.luaquote = function(str)
  if M.opts.quote_style ~= "AutoPreferDouble" then
    error("TODO(other quote_styles)")
  end
  if M.opts.quote_style == "AutoPreferDouble" then
    if str:find("\n", 1, true) then
      return ("[[\n%s]]"):format(str)
    end

    if not str:find([["]], 1, true) then
      return ([["%s"]]):format(str)
    end

    if not str:find([[']], 1, true) then
      return ([['%s']]):format(str)
    end

    if not str:find("[[", 1, true) or not str:find("]]", 1, true) then
      return ("[[%s]]"):format(str)
    end
  end
  error("TODO(string escaping), str: " .. str)
end

local lua_keywords = {
  ["and"] = true,
  ["break"] = true,
  ["do"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["end"] = true,
  ["false"] = true,
  ["for"] = true,
  ["function"] = true,
  ["goto"] = true,
  ["if"] = true,
  ["in"] = true,
  ["local"] = true,
  ["nil"] = true,
  ["not"] = true,
  ["or"] = true,
  ["repeat"] = true,
  ["return"] = true,
  ["then"] = true,
  ["true"] = true,
  ["until"] = true,
  ["while"] = true,
}

---@param str string
---@return boolean
local function contains_lua_symbol(str)
  return str:find("[%+%-%*%/%%%^#=%~<>%(%){}%[%];:,%.]") ~= nil
end

---@param str string
---@return string keystring
local tokeystring = function(str)
  if lua_keywords[str] or contains_lua_symbol(str) then
    return ("[%s]"):format(M.luaquote(str))
  end

  return str
end

---@type table<type, integer>
local typeprio = {
  ["string"] = 1,
  ["number"] = 2,
}

---@param a string|number
---@param b string|number
---@return boolean
local function sorted_strings_then_numbers(a, b)
  local atype = type(a)
  local btype = type(b)
  if atype == btype and atype == "string" or atype == "number" then
    return a < b
  end

  return typeprio[a] < typeprio[b]
end

---Iterates through `tbl` in the order specified by `keys` and generates a pretty version of valid lua code for
---constructing the table.
---@param tbl table
---@param keys any[]
---@param opts hyprtolua.FormatOpts
---@param indent0 string
local function tbl_tolua(tbl, keys, opts, indent0)
  ---@type string[]
  local lines = { "{" }
  local indent1 = indent0 .. indent(1)
  for _, k in ipairs(keys) do
    local v = tbl[k]
    local ktype = type(k)
    if ktype == "string" then
      lines[#lines + 1] = ("%s = %s,"):format(tokeystring(k), M.toluacode(v, opts, indent1))
    elseif ktype == "number" then
      lines[#lines + 1] = ("%s%s,"):format(indent1, M.toluacode(v, opts, indent1))
    else
      error("TODO: other key type printing")
    end
  end
  lines[#lines + 1] = "}"

  --post process
  local endcol = #indent0
  for _, line in ipairs(lines) do
    endcol = endcol + 1 + #line
  end
  local oneliner = endcol < opts.column_width
  if not oneliner then
    -- prepend indent to all contents
    for i = 2, #lines - 1 do
      lines[i] = indent1 .. lines[i]
    end
    lines[#lines] = indent0 .. lines[#lines]
  else
    -- remove comma from last line
    if #lines > 2 then
      local second_to_last_line = lines[#lines - 1]
      lines[#lines - 1] = second_to_last_line:sub(1, #second_to_last_line - 1)
    end
  end
  return table.concat(lines, oneliner and " " or "\n")
end

---Similar to vim.inspect, but tries to write lua code similarly to how well-formatted lua code looks like.
---Will try to write the table as a oneliner if possible.
---@param val any
---@param opts hyprtolua.FormatOpts?
---@param indent0 string?
---@return string
M.toluacode = function(val, opts, indent0)
  local valtype = type(val)
  if valtype == "string" then
    return M.luaquote(val)
  end

  if valtype ~= "table" then
    return tostring(val)
  end
  ---@type metatable
  local mt = getmetatable(val)
  if mt and mt.__tostring then
    return M.luaquote(tostring(val))
  end

  opts = opts or M.opts
  indent0 = indent0 or ""
  local keys = vim.tbl_keys(val)
  table.sort(keys, sorted_strings_then_numbers)
  return tbl_tolua(val, keys, opts, indent0)
end

---Creates a pretty string representation of the table that lists the keys in order of the keyorder.
---@generic K
---@param t table<K, any>
---@param keyorder K[]
---@param opts hyprtolua.FormatOpts?
---@param indent0 string?
---@return string pretty-print
M.tbl_toluacode = function(t, keyorder, opts, indent0)
  local keys = {}
  for _, key in ipairs(keyorder) do
    keys[key] = true
  end

  local original_keys = {}
  for k in pairs(t) do
    if not keys[k] then
      original_keys[#original_keys + 1] = k
    end
  end
  table.sort(original_keys, sorted_strings_then_numbers)
  opts = opts or M.opts
  indent0 = indent0 or ""
  return tbl_tolua(t, vim.list_extend(original_keys, keyorder), opts, indent0)
end

return M
