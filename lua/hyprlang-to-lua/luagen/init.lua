local pretty = require("hyprlang-to-lua.luagen.pretty")
local tolua = pretty.tolua
local M = {}

---@param irs hyprtolua.ir.Exec[]
---@param variant hyprtolua.ir.ExecVariant
---@param format_opts hyprtolua.FormatOpts
M.exec_to_lua = function(irs, variant, format_opts)
  ---@type string[]
  local exec_cmd_lines = {}
  for _, ir in ipairs(irs) do
    exec_cmd_lines[#exec_cmd_lines + 1] = ("%shl.exec_cmd(%s)"):format(
      pretty.indent(1),
      tolua(ir.command)
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
]]):format(tolua(event), exec_cmds_str)
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
    elseif part.name then
      ---@cast part hyprtolua.ir.Assignment
      tbl[part.name] = val_to_lua(part.value)
    end
  end
  return tbl
end
---@param ir hyprtolua.ir.Section
M.section_to_lua_code = function(ir)
  if ir.section_name == "monitorv2" then
    ---@type HL.MonitorSpec
    local monitor_opts = section_to_lua_table(ir)
    if monitor_opts.scale then
      -- Convert to a string
      monitor_opts.scale = tostring(monitor_opts.scale)
    end
    return ([[hl.monitor(%s)]]):format(tolua(monitor_opts))
  elseif ir.section_name == "windowrule" then
    return ([[hl.window_rule(%s)]]):format(tolua(section_to_lua_table(ir)))
  else
    return ([[hl.config(%s)]]):format({
      [ir.section_name] = tolua(section_to_lua_table(ir)),
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
    return ("hl.env(%s, %s)"):format(tolua(tostring(ir.params[1])), tolua(tostring(ir.params[2])))
  elseif keyword == "workspace" then
    local ws_args = {
      workspace = tostring(ir.params[1]),
    }
    local ws_argtables = {}
    for i = 2, #ir.params do
      local param = ir.params[i]
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
    return ("hl.workspace_rule(%s)"):format(pretty.generate_with_parts(ws_args, ws_argtables))
  elseif keyword == "windowrule" then
  end
  error("TODO" .. tolua(ir))
end

return M
