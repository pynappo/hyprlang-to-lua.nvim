local M = {}

---@param str string
---@return string lua_formatted_string
local toluastring = function(str)
  if not str:find([["]], 1, true) then
    return ([["%s"]]):format(str)
  elseif not str:find([[']], 1, true) then
    return ("'%s'"):format(str)
  elseif not str:find("[%[%]]") then
    return ("[[%s]]"):format(str)
  end
  error("TODO: Couldn't represent str " .. str .. " without escaping, file an issue")
end

---Based on StyLua opts, adjusted to the settings on the hyprland wiki.
---@class hyprtolua.FormatOpts
M.default_format_opts = {
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

---@param format_opts hyprtolua.FormatOpts
---@param level integer
---@return string
local indent = function(format_opts, level)
  if format_opts.indent_type == "Spaces" then
    return (" "):rep(format_opts.indent_width):rep(level)
  elseif format_opts.indent_type == "Tabs" then
    return ("\t"):rep(level)
  end
  error("Could not determine indent")
end

---@param val any
---@param opts hyprtolua.FormatOpts?
---@param idt string?
local inspect = function(val, opts, idt)
  opts = opts or M.default_format_opts
  local indent_len = idt and #idt or 0
  local estimated_length = #vim.inspect(val) + indent_len
  local oneliner = estimated_length < opts.column_width
  return vim.inspect(
    val,
    -- If the estimated length is lower than the column width, try creating a one-liner.
    { indent = oneliner and " " or indent(opts, 1), newline = oneliner and "" or "\n" }
  )
end

---@param irs hyprtolua.ir.Exec[]
---@param variant hyprtolua.ir.ExecVariant
---@param format_opts hyprtolua.FormatOpts
M.exec_to_lua = function(irs, variant, format_opts)
  ---@type string[]
  local exec_cmd_lines = {}
  for _, ir in ipairs(irs) do
    exec_cmd_lines[#exec_cmd_lines + 1] = ("%shl.exec_cmd(%s)"):format(
      indent(format_opts, 1),
      toluastring(ir.command)
    )
  end

  ---@type HL.EventName
  local event
  if variant == "exec" or variant == "execr" then
    event = "config.reloaded"
  elseif variant == "exec-once" or variant == "execr-once" then
    event = "hyprland.start"
  elseif variant == "exec-shutdown" then
    event = "hyprland.shutdown"
  end

  local exec_cmds_str = table.concat(exec_cmd_lines, "\n")
  return ([[
hl.on(%s, function()
%s
end)
]]):format(toluastring(event), exec_cmds_str)
end

---@param config_ir hyprtolua.ir.Configuration
---@param format_opts hyprtolua.FormatOpts
---@return string[] parts
M.config_to_lua = function(config_ir, format_opts)
  ---@type string[]
  local parts = {}
  for i = 1, #config_ir do
    local ir = config_ir[i]
    if ir.command then
      local execs_of_same_variant = { ir }
      ---@cast ir hyprtolua.ir.Exec
      while i < #ir and ir[i + 1].variant == ir.variant do
        table.insert(execs_of_same_variant, ir[i + 1])
        i = i + 1
      end
      parts[#parts + 1] = M.exec_to_lua(execs_of_same_variant, ir.variant, format_opts)
    elseif ir.comment then
      ---@cast ir hyprtolua.ir.Comment
      parts[#parts + 1] = "--" .. ir.comment
    elseif ir.params then
      ---@cast ir hyprtolua.ir.Keyword
      parts[#parts + 1] = M.keyword_to_lua_code(ir)
    elseif ir.section_name then
      ---@cast ir hyprtolua.ir.Section
      parts[#parts + 1] = M.section_to_lua_code(ir)
    end
  end
  return parts
end

---@param ir hyprtolua.ir.Value
local val_to_lua = function(ir)
  if type(ir) ~= "table" then
    return ir
  end
  ---@type metatable
  local mt = getmetatable(ir)
  if mt and mt.__tostring then
    return tostring(ir)
  end
  return ir
end

---@param ir hyprtolua.ir.Section
local function section_to_lua_table(ir)
  local tbl = {}
  for _, part in ipairs(ir) do
    if part.section_name then
      ---@cast part hyprtolua.ir.Section
      tbl[part.section_name] = section_to_lua_table(part)
    elseif part.keyword then
      ---@cast part hyprtolua.ir.Keyword
      tbl[part.keyword] = part.params
      error("TODO")
    elseif part.name then
      ---@cast part hyprtolua.ir.Assignment
      tbl[part.name] = val_to_lua(part.value)
    end
  end
  return tbl
end
---@param ir hyprtolua.ir.Section
---@param format_opts hyprtolua.FormatOpts
M.section_to_lua_code = function(ir, format_opts)
  if ir.section_name == "monitorv2" then
    ---@type HL.MonitorSpec
    local monitor_opts = section_to_lua_table(ir)
    if monitor_opts.scale then
      -- Convert to a string
      monitor_opts.scale = tostring(monitor_opts.scale)
    end
    return ([[hl.monitor(%s)]]):format(inspect(monitor_opts))
  elseif ir.section_name == "windowrule" then
    return ([[hl.window_rule(%s)]]):format(vim.inspect(section_to_lua_table(ir)))
  else
    return ([[hl.config(%s)]]):format({
      [ir.section_name] = vim.inspect(section_to_lua_table(ir)),
    })
  end
end

---@param param_str string
---@return table|string val
local param_string_to_val = function(param_str)
  local space_idx = param_str:find(" ", 1, true)
  local colon_idx = param_str:find(":", 1, true)
  -- forms are either key:value, key value, or subkey1:subkey2 value
  if not space_idx then
    if colon_idx then
      local key = param_str:sub(1, colon_idx - 1)
      local value = param_str:sub(colon_idx + 1)
      return { [key] = value }
    end
    return param_str
  end
  local key = param_str:sub(1, space_idx - 1)
  colon_idx = key:find(":", 1, true)
  local value = param_str:sub(space_idx + 1)
  if colon_idx then
    local subkey1 = key:sub(1, colon_idx - 1)
    local subkey2 = key:sub(colon_idx + 1)
    return {
      [subkey1] = {
        [subkey2] = value,
      },
    }
  else
    return {
      [key] = value,
    }
  end
end

---@param ir hyprtolua.ir.Keyword
---@return string
M.keyword_to_lua_code = function(ir)
  local keyword = ir.keyword
  if keyword == "env" then
    return ("hl.env(%s, %s)"):format(
      toluastring(tostring(ir.params[1])),
      toluastring(tostring(ir.params[2]))
    )
  elseif keyword == "workspace" then
    local ws_args = {
      workspace = tostring(ir.params[1]),
    }
    for i = 2, #ir.params do
      local param = ir.params[i]
      local ws_argtables = {}
      if type(param) == "string" then
        local param_in_lua = param_string_to_val(param)
        if type(param_in_lua) == "table" then
          ws_argtables[#ws_argtables + 1] = param_in_lua
        else
          error("Could not generate lua value of param: " .. param)
        end
      end
      ws_args = vim.tbl_deep_extend("force", ws_args, unpack(ws_argtables))
    end
    return ("hl.workspace_rule(%s)"):format(inspect(ws_args))
  elseif keyword == "windowrule" then
  end
  error("TODO" .. vim.inspect(ir))
end

return M
