local utils = require("hyprlang-to-lua.utils")
local M = {}
local get_node_text = vim.treesitter.get_node_text

-- /**
--  * @file Hyprlang grammar for tree-sitter
--  * @author LIOKA Ranarison Fiderana
--  * @license MIT
--  */
--
-- /// <reference types="tree-sitter-cli/dsl" />
-- // @ts-check
--
-- module.exports = grammar({
--   name: "hyprlang",
--
--   extras: ($) => [/[ \t]/, $.comment],
--
--   conflicts: ($) => [[$.number, $.legacy_hex]],
--
--   word: ($) => $.string,
--
--   rules: {
--     configuration: ($) =>
--       repeat(
--         choice(
--           $.source,
--           $.exec,
--           $.declaration,
--           $.assignment,
--           $.keyword,
--           $.section,
--           $._linebreak,
--         ),
--       ),
---@class (exact) hyprtolua.ir.Configuration
---@field [integer] hyprtolua.ir.Source|hyprtolua.ir.Exec|hyprtolua.ir.Declaration|hyprtolua.ir.Keyword|hyprtolua.ir.Section|hyprtolua.ir.Comment

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Configuration
M.parse_configuration = function(node, src)
  local config_ir = {}
  for child in node:iter_children() do
    if child:named() then
      local ir
      local statement_type = child:type()
      if statement_type == "source" then
        ir = M.parse_source(child, src)
      elseif statement_type == "exec" then
        ir = M.parse_exec(child, src)
      elseif statement_type == "declaration" then
        ir = M.parse_declaration(child, src)
      elseif statement_type == "assignment" then
        ir = M.parse_assignment_as_keyword(child, src)
      elseif statement_type == "keyword" then
        ir = M.parse_keyword(child, src)
      elseif statement_type == "section" then
        ir = M.parse_section(child, src)
      elseif statement_type == "comment" then
        ir = M.parse_comment(child, src)
      else
        error("Invalid configuration child type: " .. statement_type)
      end
      config_ir[#config_ir + 1] = ir
    end
  end
  return config_ir
end

-- declaration: ($) =>
--   seq(
--     field("name", $.variable),
--     "=",
--     field("value", choice($.mod, $.number, $.string_literal, $.color)),
--     $._linebreak,
--   ),
---@class hyprtolua.ir.Declaration
---@field name string
---@field value string|number|hyprtolua.ir.Color

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Declaration
M.parse_declaration = function(node, src)
  local name_child = assert(node:field("name")[1])
  local value_child = assert(node:field("value")[1])
  local value
  do
    local valtype = value_child:type()
    if valtype == "mod" then
      value = get_node_text(value_child, src)
    elseif valtype == "number" then
      value = assert(tonumber(get_node_text(value_child, src)))
    elseif valtype == "string_literal" then
      value = get_node_text(value_child, src)
    elseif valtype == "color" then
      value = M.parse_color(value_child, src)
    else
      error("Invalid value node type for declaration: " .. valtype)
    end
  end
  return {
    name = get_node_text(name_child, src),
    value = value,
  }
end

--
--     assignment: ($) =>
--       seq(
--         field("name", $.name),
--         "=",
--         field("value", optional($._value)),
--         $._linebreak,
--       ),

---Assignments are just keywords that have 0 or 1 param. Parsing them as such them makes the generation code simpler.
---@param node TSNode
---@param src string
---@return hyprtolua.ir.Keyword
M.parse_assignment_as_keyword = function(node, src)
  local name_child = assert(node:field("name")[1])
  ---@type hyprtolua.ir.Keyword
  local ir = {
    keyword = get_node_text(name_child, src),
    params = {
      raw = "",
    },
  }
  local value_child = node:field("value")[1]
  if value_child then
    ir.params[#ir.params + 1] = M.parse_value(value_child, src)
    ir.params.raw = get_node_text(value_child, src)
  end
  return ir
end
--
--     keyword: ($) =>
--       seq(
--         field("keyword", $.name),
--         "=",
--         field("value", $.params),
--         $._linebreak,
--       ),
---@class (exact) hyprtolua.ir.Keyword
---@field keyword string
---@field params hyprtolua.ir.Params

---@param node TSNode
---@param src string
M.parse_keyword = function(node, src)
  local keyword_child = assert(node:field("keyword")[1])
  local value_child = assert(node:field("value")[1])
  local params_ir = M.parse_params(value_child, src)

  if node:child(2):type() == "ERROR" then
    -- happens in keyword=,paramtable.insert(params_ir, 1, "")2
    table.insert(params_ir, 1, "")
    params_ir.raw = "," .. params_ir.raw
  end

  ---@type hyprtolua.ir.Keyword
  return {
    keyword = get_node_text(keyword_child, src),
    params = params_ir,
  }
end

--
--     section: ($) =>
--       seq(
--         seq(
--           field("name", $.name),
--           optional(seq(":", field("device", $.device_name))),
--         ),
--         "{",
--         $._linebreak,
--         repeat(choice($.assignment, $.keyword, $.section, $._linebreak)),
--         "}",
--         $._linebreak,
--       ),
---@class (exact) hyprtolua.ir.Section
---@field section_name string
---@field device string?
---@field [integer] hyprtolua.ir.Keyword|hyprtolua.ir.Section

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Section
M.parse_section = function(node, src)
  local name_node = assert(node:field("name")[1])
  local name = get_node_text(name_node, src)
  local device_node = node:field("device")[1]
  local device = nil
  if device_node then
    device = get_node_text(device_node, src)
  end
  ---@type hyprtolua.ir.Section
  local ir = {
    section_name = name,
    device = device,
  }
  for child in node:iter_children() do
    if child:named() then
      local childtype = child:type()
      if childtype == "assignment" then
        ir[#ir + 1] = M.parse_assignment_as_keyword(child, src)
      elseif childtype == "keyword" then
        ir[#ir + 1] = M.parse_keyword(child, src)
      elseif childtype == "section" then
        ir[#ir + 1] = M.parse_section(child, src)
      end
    end
  end
  return ir
end
--
--     source: ($) => seq("source", "=", $.string, $._linebreak),
---@class (exact) hyprtolua.ir.Source
---@field source string

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Source
M.parse_source = function(node, src)
  local string_node = assert(node:child(2), "could not find string for source node")
  ---@type hyprtolua.ir.Source
  return { source = vim.trim(get_node_text(string_node, src)) }
end
--
--     arguments: ($) =>
--       repeat1(choice($.number, alias($._window_rule_argument, $.string))),
---@class (exact) hyprtolua.ir.Arguments
---@field [integer] number|string

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Arguments
M.parse_arguments = function(node, src)
  ---@type hyprtolua.ir.Arguments
  local ir = {}
  for argnode in node:iter_children() do
    local text = get_node_text(argnode, src)
    if argnode:type() == "number" then
      ir[#ir + 1] = tonumber(text)
    elseif argnode:type() == "string" then
      ir[#ir + 1] = text
    end
  end
  return ir
end
--
--     window_rule: ($) => seq($.name, optional($.arguments)),
---@class (exact) hyprtolua.ir.WindowRule
---@field name string
---@field arguments hyprtolua.ir.Arguments

---@param node TSNode
---@param src string
---@return hyprtolua.ir.WindowRule
M.parse_windowrule = function(node, src)
  local name_child = assert(node:child(0))
  local arguments_child = assert(node:child(1))
  ---@type hyprtolua.ir.WindowRule
  return {
    name = get_node_text(name_child, src),
    arguments = M.parse_arguments(arguments_child, src),
  }
end
--
--     rules: ($) => seq("[", $.window_rule, repeat(seq(";", $.window_rule)), "]"),
---@alias hyprtolua.ir.Rules hyprtolua.ir.WindowRule[]

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Rules
M.parse_rules = function(node, src)
  local window_rule_children = node:named_children()
  ---@type hyprtolua.ir.Rules
  local ir = {}
  for _, window_rule_child in ipairs(window_rule_children) do
    ir[#ir + 1] = M.parse_windowrule(window_rule_child, src)
  end
  return {}
end
--
--     exec: ($) =>
--       choice(
--         seq(
--           choice("exec-once", "exec"),
--           "=",
--           optional($.rules),
--           $.string,
--           $._linebreak,
--         ),
--         seq(
--           choice("execr-once", "execr", "exec-shutdown"),
--           "=",
--           $.string,
--           $._linebreak,
--         ),
--       ),

---@alias hyprtolua.ir.ExecVariant
---|"exec"
---|"exec-once"
---|"execr-once"
---|"execr"
---|"exec-shutdown"

---@class (exact) hyprtolua.ir.Exec
---@field variant hyprtolua.ir.ExecVariant
---@field rules hyprtolua.ir.Rules?
---@field command string

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Exec
M.parse_exec = function(node, src)
  local variant_node = assert(node:child(0))
  local rules
  local str
  local child2 = assert(node:child(2))
  local child3 = assert(node:child(3))
  if child2:type() == "rules" then
    rules = M.parse_rules(child2, src)
    str = get_node_text(child3, src)
  else
    str = get_node_text(child2, src)
  end
  ---@type hyprtolua.ir.Exec
  return {
    variant = get_node_text(variant_node, src),
    rules = rules,
    command = vim.trim(str),
  }
end

--
--     _value: ($) =>
--       choice(
--         $.boolean,
--         $.number,
--         $.vec2,
--         $.display,
--         $.gradient,
--         $.mod,
--         $.keys,
--         $.string,
--         $.variable,
--         prec(1, $.color),
--         prec(1, $.position),
--       ),
---@alias hyprtolua.ir.Value
---|boolean
---|number
---|hyprtolua.ir.Vec2
---|hyprtolua.ir.Display
---|hyprtolua.ir.Gradient
---|hyprtolua.ir.Mod
---|hyprtolua.ir.Keys
---|string
---|hyprtolua.ir.Variable
---|hyprtolua.ir.Color
---|hyprtolua.ir.Position

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Value
M.parse_value = function(node, src)
  local nodetype = node:type()
  if nodetype == "boolean" then
    return M.parse_boolean(node, src)
  elseif nodetype == "number" then
    return assert(tonumber(get_node_text(node, src)))
  elseif nodetype == "vec2" then
    return M.parse_vec2(node, src)
  elseif nodetype == "display" then
    return M.parse_display(node, src)
  elseif nodetype == "gradient" then
    return M.parse_gradient(node, src)
  elseif nodetype == "mod" then
    return vim.trim(get_node_text(node, src))
  elseif nodetype == "keys" then
    return M.parse_keys(node, src)
  elseif nodetype == "string" then
    return vim.trim(get_node_text(node, src))
  elseif nodetype == "variable" then
    return M.parse_variable(node, src)
  elseif nodetype == "color" then
    return M.parse_color(node, src)
  elseif nodetype == "position" then
    return M.parse_position(node, src)
  else
    error("Invalid value type: " .. utils.inspect_tsnode(node, src))
  end
end
--
--     boolean: () => choice("true", "false", "on", "off", "yes", "no"),
---@param node TSNode
---@param src string
---@return boolean
M.parse_boolean = function(node, src)
  return vim.tbl_contains({ "true", "yes", "on" }, vim.trim(get_node_text(node, src)))
end
--
--     number: ($) =>
--       choice($._zero, seq(optional(choice("+", "-")), /[0-9][0-9\.]*/)),
--
--     vec2: ($) => seq($.number, $.number),
---@class (exact) hyprtolua.ir.Vec2
---@field [1] number
---@field [2] number

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Color
M.parse_vec2 = function(node, src)
  local child0 = assert(node:child(0))
  local child1 = assert(node:child(1))
  local str0 = get_node_text(child0, src)
  local str1 = get_node_text(child1, src)
  return { tonumber(str0), tonumber(str1) }
end

--     color: ($) => choice($.legacy_hex, $.rgb),
--     legacy_hex: ($) => seq($._zero, "x", $.hex),
---@alias hyprtolua.ir.Color
---|hyprtolua.ir.Hex
---|hyprtolua.ir.RGB
---|{ raw: string }

---@type metatable
local color_mt = {
  ---@param color hyprtolua.ir.Color
  __tostring = function(color)
    return color.raw
  end,
}

---@class hyprtolua.ir.WithRawText
---@field raw string

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Color
M.parse_color = function(node, src)
  local child = assert(node:child(0))
  local childtype = child:type()
  ---@type hyprtolua.ir.Color
  local color = {}
  if childtype == "rgb" then
    color = M.parse_RGB(child, src)
  elseif childtype == "legacy_hex" then
    local hex_child = assert(child:child(0)):child(2)
    assert(hex_child)
    ---@type hyprtolua.ir.Color
    color = {
      hex = get_node_text(hex_child, src),
    }
  else
    error("Invalid color node child: " .. childtype)
  end
  --- Wrap with color metatable
  color.raw = vim.trim(get_node_text(node, src))
  setmetatable(color, color_mt)
  return color
end

--     rgb: ($) =>
--       seq(choice("rgb", "rgba"), "(", choice($.hex, $.number_tuple), ")"),
---@class (exact) hyprtolua.ir.RGB
---@field color_format "rgb"|"rgba"
---@field [integer] number?
---@field hex string?

---@param node TSNode
---@param src string
---@return hyprtolua.ir.RGB
M.parse_RGB = function(node, src)
  local rgb_or_rgba_child = assert(node:child(0))
  local value_child = assert(node:child(2))
  ---@type hyprtolua.ir.RGB
  local ir = {
    color_format = rgb_or_rgba_child:type() == "rgba" and "rgba" or "rgb",
    raw = get_node_text(node, src),
  }
  local valtype = value_child:type()
  if valtype == "hex" then
    ir.hex = get_node_text(value_child, src)
  elseif valtype == "number_tuple" then
    for _, number_node in ipairs(value_child:named_children()) do
      ir[#ir + 1] = tonumber(get_node_text(number_node, src))
    end
  else
    error("Invalid rgb value")
  end
  return ir
end
--
--     gradient: ($) => seq($.color, repeat($.color), optional($.angle)),
---@class (exact) hyprtolua.ir.Gradient
---@field [integer] hyprtolua.ir.Color
---@field angle hyprtolua.ir.Angle?

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Gradient
M.parse_gradient = function(node, src)
  ---@type hyprtolua.ir.Gradient
  local ir = {}
  for child in node:iter_children() do
    local childtype = child:type()
    if childtype == "color" then
      ir[#ir + 1] = M.parse_color(node, src)
    elseif childtype == "angle" then
      local angle_grandchild = assert(child:child(0))
      ---@type hyprtolua.ir.Angle
      local angle_ir = {
        deg = tonumber(get_node_text(angle_grandchild, src)) --[[@as integer]],
      }
      ir.angle = angle_ir
    else
      error("Invalid gradient node child: " .. childtype)
    end
  end
  return ir
end
--
--     number_tuple: ($) => seq($.number, repeat(seq(",", $.number))),
--
--     display: ($) => seq($.position, optional(seq("@", $.number))),
---@class (exact) hyprtolua.ir.Display
---@field position hyprtolua.ir.Position
---@field refresh_rate number?

---@type metatable
local display_mt = {
  ---@param self hyprtolua.ir.Display
  __tostring = function(self)
    if not self.refresh_rate then
      return tostring(self.position)
    end
    return ("%s@%s"):format(tostring(self.position), self.refresh_rate)
  end,
}
---@param node TSNode
---@param src string
---@return hyprtolua.ir.Display
M.parse_display = function(node, src)
  local position_child = assert(node:child(0))
  ---@type hyprtolua.ir.Display
  local ir = {
    position = M.parse_position(position_child, src),
  }
  if node:child_count() > 1 then
    local refresh_rate_child = assert(node:child(2))
    ir.refresh_rate = tonumber(get_node_text(refresh_rate_child, src))
  end
  return setmetatable(ir, display_mt)
end
--
--     position: ($) => seq($.number, "x", $.number),
---@class (exact) hyprtolua.ir.Position
---@field x number
---@field y number

---@type metatable
local position_mt = {
  ---@param self hyprtolua.ir.Position
  __tostring = function(self)
    return ("%sx%s"):format(self.x, self.y)
  end,
}
---@param node TSNode
---@param src string
---@return hyprtolua.ir.Position
M.parse_position = function(node, src)
  local x_child = assert(node:child(0))
  local y_child = assert(node:child(2))
  ---@type hyprtolua.ir.Position
  local ir = {
    x = assert(tonumber(get_node_text(x_child, src))),
    y = assert(tonumber(get_node_text(y_child, src))),
  }
  return setmetatable(ir, position_mt)
end
--
--     hex: () => /[0-9a-fA-F]{6,8}/,
---@class (exact) hyprtolua.ir.Hex
---@field hex string
--
--     angle: () => seq(/[0-9]{1,3}/, "deg"),
---@class (exact) hyprtolua.ir.Angle
---@field deg integer
--
--     mod: () =>
--       choice(
--         "SHIFT",
--         "CAPS",
--         "CTRL",
--         "CONTROL",
--         "ALT",
--         "ALT_L",
--         "MOD2",
--         "MOD3",
--         "SUPER",
--         "WIN",
--         "LOGO",
--         "MOD4",
--         "MOD5",
--         "TAB",
--       ),
---@alias hyprtolua.ir.Mod
---|"SHIFT"
---|"CAPS"
---|"CTRL"
---|"CONTROL"
---|"ALT"
---|"ALT_L"
---|"MOD2"
---|"MOD3"
---|"SUPER"
---|"WIN"
---|"LOGO"
---|"MOD4"
---|"MOD5"
---|"TAB"
--
--     keys: ($) => choice(seq($.mod, $.mod), seq($.variable, $.mod)),
---@class (exact) hyprtolua.ir.Keys
---@field [1] hyprtolua.ir.Mod|hyprtolua.ir.Variable
---@field [2] hyprtolua.ir.Mod

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Keys
M.parse_keys = function(node, src)
  local child0 = assert(node:child(0))
  local child1 = assert(node:child(1))
  ---@type hyprtolua.ir.Keys
  local ir = {
    child0:type() == "variable" and M.parse_variable(child0, src) or get_node_text(child0, src),
    get_node_text(child1, src),
  }
  return ir
end
--
--     string: () => token(prec(-1, /[^\n,#]+|.*##.*/)),
--
--     string_literal: () => token(prec(-1, /[^\n#]+|.*##.*/)),
--
--     params: ($) =>
--       prec(-1, seq($._value, repeat(seq(",", optional($._value))))),
---@class hyprtolua.ir.Params
---@field [integer] hyprtolua.ir.Value
---@field raw string

---Currently tree-sitter-hyprlang does not properly read all mods (e.g. SUPER_L). This works around that for now.
---@param modnode TSNode
---@param errnode TSNode
---@param src string
---@return hyprtolua.ir.Mod?
local reparse_mod_with_error = function(modnode, errnode, src)
  if modnode:type() ~= "mod" then
    return nil
  end
  return get_node_text(modnode, src) .. get_node_text(errnode, src)
end
---@param node TSNode
---@param src string
---@return hyprtolua.ir.Params
M.parse_params = function(node, src)
  ---@type hyprtolua.ir.Params
  local ir = {
    raw = vim.trim(get_node_text(node, src)),
  }
  for child in node:iter_children() do
    if child:type() ~= "," then
      if child:has_error() then
        local prev_child = child:prev_sibling()
        if prev_child and prev_child:type() == "mod" then
          ir[#ir] = reparse_mod_with_error(prev_child, child, src)
        end
      else
        ir[#ir + 1] = M.parse_value(child, src)
      end
    end
  end
  return ir
end
--
--     name: () => /[\w][\w\d\.\-]*/,
--
--     device_name: () => /[\w\d][\w\d\/\.\-:]*/,
--
--     variable: () => seq("$", field("name", /\w[\w\d]*/)),
---@class (exact) hyprtolua.ir.Variable
---@field name string

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Variable
M.parse_variable = function(node, src)
  local name_child = assert(node:field("name")[1])
  ---@type hyprtolua.ir.Variable
  local ir = {
    name = get_node_text(name_child, src),
  }
  return ir
end
--
--     _zero: () => "0",
--
--     _window_rule_argument: () => /[^\]\s;,]+/,
--
--     _linebreak: () => "\n",
--
--     comment: () => seq("#", /.*/),
---@class (exact) hyprtolua.ir.Comment
---@field comment string

---@param node TSNode
---@param src string
---@return hyprtolua.ir.Comment
M.parse_comment = function(node, src)
  ---@type hyprtolua.ir.Comment
  local ir = {
    comment = get_node_text(node, src):sub(2),
  }
  return ir
end
--   },
-- });

return M
