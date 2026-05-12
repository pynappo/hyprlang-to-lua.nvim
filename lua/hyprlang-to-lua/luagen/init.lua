local pretty = require("hyprlang-to-lua.luagen.pretty")
local utils = require("hyprlang-to-lua.utils")
local migrate = require("hyprlang-to-lua.luagen.migrate")
local toluacode = pretty.toluacode
local M = {}

---@param irs hyprtolua.ir.Exec[]
---@param variant hyprtolua.ir.ExecVariant
---@nodiscard
M.exec_toluacode = function(irs, variant)
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
end)]]):format(toluacode(event), exec_cmds_str)
end

---@param s string
---@param additional_levels integer
---@return string
---@nodiscard
local indent_str = function(s, additional_levels)
  local additional_indent = pretty.indent(additional_levels)
  local indented = (additional_indent .. s):gsub("\n", "\n" .. additional_indent)
  return indented
end

---@param ir hyprtolua.ir.Keyword
---@param last_submap string?
---@return string? submap
---@return string chunk
local function parse_submap(ir, last_submap)
  local chunks = {}
  ---@type string?, string?
  local submap, submap_on_dispatch
  if ir.keyword then
    submap, submap_on_dispatch = unpack(ir.params)
  end

  assert(type(submap) == "string")
  local is_reset_submap = submap == "reset"

  if last_submap then
    chunks[#chunks + 1] = "end)"
  end

  if not is_reset_submap then
    if not submap_on_dispatch then
      chunks[#chunks + 1] = ("hl.define_submap(%s, function()"):format(toluacode(submap))
    else
      chunks[#chunks + 1] = ("hl.define_submap(%s, %s, function()"):format(
        toluacode(submap),
        toluacode(submap_on_dispatch)
      )
    end
  end

  return not is_reset_submap and submap or nil, table.concat(chunks, "\n")
end

local chunks = {}
---@param config_ir hyprtolua.ir.Configuration
---@return string[] chunks
---@nodiscard
M.config_toluacode = function(config_ir)
  ---@type string[]
  chunks = {}
  ---@type string?
  local submap = nil
  for i = 1, #config_ir do
    local ir = config_ir[i]
    if ir.command then
      local execs_of_same_variant = { ir }
      ---@cast ir hyprtolua.ir.Exec
      while i < #ir and ir[i + 1].variant == ir.variant do
        table.insert(execs_of_same_variant, ir[i + 1])
        i = i + 1
      end
      chunks[#chunks + 1] = M.exec_toluacode(execs_of_same_variant, ir.variant)
    elseif ir.comment then
      ---@cast ir hyprtolua.ir.Comment
      chunks[#chunks + 1] = "--" .. ir.comment
    elseif ir.params then
      ---@cast ir hyprtolua.ir.Keyword
      local chunk
      if ir.keyword == "submap" then
        submap, chunk = parse_submap(ir, submap)
      else
        chunk = M.keyword_toluacode(ir)
        if submap then
          chunk = indent_str(chunk, 1)
        end
      end

      chunks[#chunks + 1] = chunk
    elseif ir.section_name then
      ---@cast ir hyprtolua.ir.Section
      chunks[#chunks + 1] = M.section_toluacode(ir)
    elseif ir.source then
      local path_to_source = vim.fs.normalize(ir.source)
      local require_path
      if vim.startswith(path_to_source, utils.config_hypr_path .. "/") then
        local path_from_config_dir = path_to_source:sub(#utils.config_hypr_path + 2)
        require_path = path_from_config_dir:gsub("/", "."):gsub("%.conf$", "")
      end
      if require_path then
        chunks[#chunks + 1] = ("require(%s)"):format(toluacode(require_path))
      else
        chunks[#chunks + 1] = ("-- require(%s) -- hyprlang-to-lua: could not convert this path to require() equivalent"):format(
          toluacode(ir.source)
        )
      end
    end
  end
  if submap then
    chunks[#chunks + 1] = "end)"
  end
  return chunks
end

---@param t table
---@param keys any[]k
---@param value any
local tbl_set = function(t, keys, value)
  local node = t
  for i = 1, #keys - 1 do
    local k = keys[i]
    if node[k] == nil then
      -- add a table to the node (i.e. the part of t) that doesn't have one
      node[k] = {}
    end
    node = node[k]
  end

  -- Set the last value
  node[keys[#keys]] = value
end

---@param section_ir hyprtolua.ir.Section
---@return table section
---@return any[] section_keyorder
local function section_to_tbl_and_keys(section_ir)
  local tbl = {}
  local parts = {}
  local section_keyorder = {}
  for _, ir in ipairs(section_ir) do
    local k, v
    if ir.section_name then
      ---@cast ir hyprtolua.ir.Section
      k = ir.section_name
      v, _ = section_to_tbl_and_keys(ir)
    elseif ir.keyword then
      ---@cast ir hyprtolua.ir.Keyword
      k = ir.keyword
      local first_param = ir.params[1]
      if first_param ~= nil then
        v = first_param
      else
        first_param = ir.params.raw
      end
    else
      error("TODO: unparsed ir in section: " .. pretty.toluacode(ir))
    end

    k = utils.tosnakecase(k)

    local part = {}
    local keys = vim.split(k, ".", { plain = true })
    tbl_set(part, keys, v)
    parts[#parts + 1] = part
    section_keyorder[#section_keyorder + 1] = keys[1]
  end
  if #parts > 0 then
    tbl = vim.tbl_deep_extend("force", {}, unpack(parts))
  end
  return tbl, section_keyorder
end

---@param ir hyprtolua.ir.Section
---@nodiscard
M.section_toluacode = function(ir)
  if ir.section_name == "monitorv2" then
    ---@type HL.MonitorSpec
    local monitor_opts, keys = section_to_tbl_and_keys(ir)
    if monitor_opts.scale then
      -- Convert to a string
      monitor_opts.scale = tostring(monitor_opts.scale)
    end
    return ([[hl.monitor(%s)]]):format(pretty.tbl_toluacode(monitor_opts, keys))
  elseif ir.section_name == "windowrule" then
    local window_rule_spec, keys = section_to_tbl_and_keys(ir)
    migrate.window_rule(window_rule_spec)
    return ([[hl.window_rule(%s)]]):format(pretty.tbl_toluacode(window_rule_spec, keys))
  end
  local indent1 = pretty.indent(1)
  local config, keys = section_to_tbl_and_keys(ir)
  return ([[
hl.config({
%s%s = %s
})]]):format(
    indent1,
    pretty.tokeystring(ir.section_name),
    pretty.tbl_toluacode(config, keys, indent1)
  )
end

---Parses a parameter into a value and potentially its key:
---key:val, key val, or subkey1:subkey2 val
---If the parameter matches none of the above formats, returns the string itself.
---@param param_str string
---@return table|string val
---@return string? key
local param_string_to_val = function(param_str)
  local space_idx = param_str:find(" ", 1, true)
  local colon_idx = param_str:find(":", 1, true)
  if not space_idx then
    if not colon_idx then
      return param_str
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

---Takes a table and merges in keyword parameters from params's (start or 1) until (j or #ir.params.)
---@param tbl table
---@param params hyprtolua.ir.Params
---@param i integer?
---@param j integer?
---@return any[] keys
local function merge_params(tbl, params, i, j)
  local keys = {}
  for idx = i or 1, j or #params do
    local param = params[idx]
    if type(param) == "string" then
      local val, key = param_string_to_val(param)
      assert(key, "Expected parameter to have a key" .. param)
      key = utils.tosnakecase(key)
      keys[#keys + 1] = key
      if tbl[key] == nil then
        ---@diagnostic disable-next-line: assign-type-mismatch
        tbl[key] = val
      elseif type(val) == "table" then
        ---@diagnostic disable-next-line: assign-type-mismatch
        tbl[key] = vim.tbl_deep_extend("force", tbl[key], val)
      else
        chunks[#chunks + 1] = ("-- hyprlang-to-lua: for below, did not merge in key-value pair: %s, %s"):format(
          key,
          val
        )
      end
    else
      error("Could not parse parameter" .. param)
    end
  end
  return keys
end

---@type table<string, HL.BindOptions>
local flagchars_to_kv = {
  l = { locked = true },
  r = { release = true },
  c = { click = true },
  g = { drag = true },
  o = { long_press = true },
  e = { repeating = true },
  n = { non_consuming = true },
  m = { mouse = true },
  t = { transparent = true },
  i = { ignore_mods = true },
  s = { separate = true },
  p = { bypass = true },
  u = { submap_universal = true },
}
local bindopts_keys = ("[%s]"):format(table.concat(vim.tbl_keys(flagchars_to_kv)))
---@param flagstr string
---@return HL.BindOptions
---@return string[] keyorder
local function bindopts_from_flagstring(flagstr)
  ---@type HL.BindOptions
  local tbl = {}
  local keyorder = {}
  for k in flagstr:gmatch(bindopts_keys) do
    tbl = vim.tbl_deep_extend("force", tbl, flagchars_to_kv[k])
    keyorder[#keyorder + 1] = k
  end
  return tbl, keyorder
end

---@param ir hyprtolua.ir.Keyword
---@return string
---@nodiscard
M.keyword_toluacode = function(ir)
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
    local keys_by_merge_order = merge_params(ws_rule, ir.params, 2)
    migrate.workspace_rule(ws_rule, keys_by_merge_order)
    return ("hl.workspace_rule(%s)"):format(pretty.tbl_toluacode(ws_rule, keys_by_merge_order))
  elseif keyword == "windowrule" then
    ---@type HL.WindowRuleSpec
    local window_rule_spec = {}
    local keys = merge_params(window_rule_spec, ir.params)

    migrate.window_rule(window_rule_spec)
    return ("hl.window_rule(%s)"):format(pretty.tbl_toluacode(window_rule_spec, keys))
  elseif keyword == "bezier" then
    local name, x0, y0, x1, y1 = unpack(ir.params)
    return ("hl.curve(%s, %s)"):format(
      toluacode(name),
      pretty.tbl_toluacode({
        type = "bezier",
        points = {
          { x0, y0 },
          { x1, y1 },
        },
      }, { "type", "points" }, nil, math.huge)
    )
  elseif keyword == "animation" then
    local leaf, enabled_int, speed, curve, style = unpack(ir.params)
    return ("hl.animation(%s)"):format(pretty.tbl_toluacode({
      leaf = leaf,
      enabled = enabled_int == 1,
      speed = speed,
      bezier = curve,
      style = style,
    }, { "leaf", "enabled", "speed", "bezier", "style" }, nil, math.huge))
  elseif vim.startswith(keyword, "bind") then
    local flagstr = keyword:sub(5)
    local bind_opts, keyorder = bindopts_from_flagstring(flagstr)
    local modstring, key, desc, dispatcher, dispatcher_params

    ---HACK: hyprlang treesitter is pretty bad with parsing keybinds so we'll just parse manually
    local raw_params = ir.params.raw
    if flagstr:find("d") then
      ---mods, key, dispatcher(, params)
      ---mods, key, desc, dispatcher(, params)
      ---@type string, string, string, string, string
      modstring, key, desc, dispatcher, dispatcher_params =
        raw_params:match("^([^,]*),%s*([^,]*),%s*([^,]+),%s*([^,]+)%s*,?%s*(.*)")
      bind_opts.desc = desc
    else
      ---@type string, string, string, string
      modstring, key, dispatcher, dispatcher_params =
        raw_params:match("^([^,]*),%s*([^,]*),%s*([^,]+)%s*,?%s*(.*)")
    end

    local lhs = migrate.bind_mod_and_keys_to_lhs(modstring, key)
    local dispatcher_code = require("hyprlang-to-lua.luagen.dispatchers").dispatcher_toluacode(
      dispatcher,
      dispatcher_params,
      lhs
    )

    local lhs_code = toluacode(lhs)
    if vim.tbl_isempty(bind_opts) then
      return ("hl.bind(%s, %s)"):format(lhs_code, dispatcher_code)
    end

    return ("hl.bind(%s, %s, %s)"):format(
      lhs_code,
      dispatcher_code,
      pretty.tbl_toluacode(bind_opts, keyorder)
    )
  elseif keyword == "blurls" then
    return ("hl.layer_rule(%s)"):format(pretty.tbl_toluacode({
      match = {
        class = ir.params[1],
      },
      blur = true,
    }, { "match", "blur" }))
  elseif keyword == "layerrule" then
    local layer_rule = {}
    local keys_by_merge_order = merge_params(layer_rule, ir.params)
    return ("hl.layer_rule(%s)"):format(pretty.tbl_toluacode(layer_rule, keys_by_merge_order))
  end
  error("TODO keyword:" .. toluacode(ir))
end

return M
