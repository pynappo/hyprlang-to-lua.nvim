local pretty = require("hyprlang-to-lua.luagen.pretty")
local toluacode = pretty.toluacode
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
      toluacode(ir.command)
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
]]):format(toluacode(event), exec_cmds_str)
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

---@param ir hyprtolua.ir.Section
---@return table section_lua
---@return any[] keys
local function section_to_tbl_and_keys(ir)
  local tbl = {}
  local parts = {}
  local keys = {}
  for _, part in ipairs(ir) do
    local k, v
    if part.section_name then
      ---@cast part hyprtolua.ir.Section
      k = part.section_name
      v, _ = section_to_tbl_and_keys(part)
    elseif part.keyword then
      ---@cast part hyprtolua.ir.Keyword
      k = part.keyword
      v = part.params
    elseif part.name then
      ---@cast part hyprtolua.ir.Assignment
      k = part.name
      v = part.value
    else
      error("TODO: unparsed ir in section: " .. pretty.toluacode(ir))
    end
    parts[#parts + 1] = { [k] = v }
    keys[#keys + 1] = k
  end
  tbl = vim.tbl_deep_extend("force", {}, unpack(parts))
  return tbl, keys
end
---@param ir hyprtolua.ir.Section
M.section_to_lua_code = function(ir)
  if ir.section_name == "monitorv2" then
    ---@type HL.MonitorSpec
    local monitor_opts, keys = section_to_tbl_and_keys(ir)
    if monitor_opts.scale then
      -- Convert to a string
      monitor_opts.scale = tostring(monitor_opts.scale)
    end
    return ([[hl.monitor(%s)]]):format(pretty.tbl_toluacode(monitor_opts, keys))
  elseif ir.section_name == "windowrule" then
    local kvs, keys = section_to_tbl_and_keys(ir)
    local windowrule_opts = vim.tbl_deep_extend("force", {}, unpack(kvs))
    return ([[hl.window_rule(%s)]]):format(pretty.tbl_toluacode(windowrule_opts, keys))
  else
    return ([[hl.config(%s)]]):format({
      [ir.section_name] = toluacode(section_to_tbl_and_keys(ir)),
    })
  end
end

---@param param_str string
---@return table|string val
---@return string key
local param_string_to_val = function(param_str)
  local space_idx = param_str:find(" ", 1, true)
  local colon_idx = param_str:find(":", 1, true)
  -- forms are either key:value, key value, or subkey1:subkey2 value
  if not space_idx then
    if not colon_idx then
      error("Could not parse parameter to value" .. param_str)
    end
    local key = param_str:sub(1, colon_idx - 1)
    local value = param_str:sub(colon_idx + 1)
    return value, key
  end

  local key = param_str:sub(1, space_idx - 1)
  colon_idx = key:find(":", 1, true)
  local value = param_str:sub(space_idx + 1)
  if colon_idx then
    local subkey1 = key:sub(1, colon_idx - 1)
    local subkey2 = key:sub(colon_idx + 1)
    return {
      [subkey2] = value,
    }, subkey1
  end
  return value, key
end

---@param ir hyprtolua.ir.Keyword
---@return string
M.keyword_to_lua_code = function(ir)
  local keyword = ir.keyword
  if keyword == "env" then
    return ("hl.env(%s, %s)"):format(
      toluacode(tostring(ir.params[1])),
      toluacode(tostring(ir.params[2]))
    )
  elseif keyword == "workspace" then
    ---@type HL.WorkspaceRuleSpec
    local ws_rule = {
      workspace = tostring(ir.params[1]),
    }
    local keys = {}
    for i = 2, #ir.params do
      local param = ir.params[i]
      if type(param) == "string" then
        local val, key = param_string_to_val(param)
        keys[#keys + 1] = key
        if ws_rule[key] == nil then
          ---@diagnostic disable-next-line: assign-type-mismatch
          ws_rule[key] = val
        elseif type(val) == "table" then
          ---@diagnostic disable-next-line: assign-type-mismatch
          ws_rule[key] = vim.tbl_deep_extend(ws_rule[key], val)
        else
          error("Could not parse value as ")
        end
      end
    end
    return ("hl.workspace_rule(%s)"):format(pretty.tbl_toluacode(ws_rule, keys))
  elseif keyword == "windowrule" then
  end
  error("TODO" .. toluacode(ir))
end

return M
