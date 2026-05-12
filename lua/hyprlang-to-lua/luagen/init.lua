local pretty = require("hyprlang-to-lua.luagen.pretty")
local utils = require("hyprlang-to-lua.utils")
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
---@param config_ir hyprtolua.ir.Configuration
---@return string[] chunks
---@nodiscard
M.config_toluacode = function(config_ir)
  ---@type string[]
  local chunks = {}
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
      chunks[#chunks + 1] = ("require(%s)"):format(toluacode(ir.source):gsub("%.conf$", ".lua"))
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
      v = first_param ~= nil and first_param or ir.params.raw
    else
      error("TODO: unparsed ir in section: " .. pretty.toluacode(ir))
    end

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
    local windowrule_opts, keys = section_to_tbl_and_keys(ir)
    return ([[hl.window_rule(%s)]]):format(pretty.tbl_toluacode(windowrule_opts, keys))
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
local function merge_keyword_params(tbl, params, i, j)
  local keys = {}
  for idx = i or 1, j or #params do
    local param = params[idx]
    if type(param) == "string" then
      local val, key = param_string_to_val(param)
      assert(key, "Expected parameter to have a key" .. param)
      keys[#keys + 1] = key
      if tbl[key] == nil then
        ---@diagnostic disable-next-line: assign-type-mismatch
        tbl[key] = val
      elseif type(val) == "table" then
        ---@diagnostic disable-next-line: assign-type-mismatch
        tbl[key] = vim.tbl_deep_extend("force", tbl[key], val)
      else
        error("Could not parse parameter" .. param)
      end
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
    local keys_by_merge_order = merge_keyword_params(ws_rule, ir.params, 2)
    return ("hl.workspace_rule(%s)"):format(pretty.tbl_toluacode(ws_rule, keys_by_merge_order))
  elseif keyword == "windowrule" then
    local windowrule_opts = {}
    local keys = merge_keyword_params(windowrule_opts, ir.params)
    return ("hl.window_rule(%s)"):format(pretty.tbl_toluacode(windowrule_opts, keys))
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
      curve = curve,
      style = style,
    }, { "leaf", "enabled", "speed", "curve", "style" }, nil, math.huge))
  elseif vim.startswith(keyword, "bind") then
    local flagstr = keyword:sub(5)
    local bind_opts, keyorder = bindopts_from_flagstring(flagstr)
    local mods, key, desc, dispatcher, dispatcher_params

    ---HACK: hyprlang treesitter is pretty bad with parsing keybinds so we'll just parse manually
    local raw_params = ir.params.raw
    if flagstr:find("d") then
      ---mods, key, dispatcher(, params)
      ---mods, key, desc, dispatcher(, params)
      mods, key, desc, dispatcher, dispatcher_params =
        raw_params:match("^([^,]*),%s*([^,]*),%s*([^,]+),%s*([^,]+)%s*,?%s*(.*)")
    else
      mods, key, dispatcher, dispatcher_params =
        raw_params:match("^([^,]*),%s*([^,]*),%s*([^,]+)%s*,?%s*(.*)")
    end
    bind_opts.desc = desc

    local modkey_luacode = toluacode(utils.istruthy(mods) and ("%s + %s"):format(mods, key) or key)
    local dispatcher_code = require("hyprlang-to-lua.luagen.dispatchers").dispatcher_toluacode(
      dispatcher,
      dispatcher_params
    )
    if vim.tbl_isempty(bind_opts) then
      return ("hl.bind(%s, %s)"):format(modkey_luacode, dispatcher_code)
    end

    return ("hl.bind(%s, %s, %s)"):format(
      modkey_luacode,
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
    local keys_by_merge_order = merge_keyword_params(layer_rule, ir.params)
    return ("hl.layer_rule(%s)"):format(pretty.tbl_toluacode(layer_rule, keys_by_merge_order))
  end
  error("TODO keyword:" .. toluacode(ir))
end

---@param chunks string[]
---@nodiscard
M.optimize = function(chunks)
  ---@type string[]
  local optimized_chunks = {}

  for i = 1, #chunks do
    local chunk = chunks[i]

    -- Pattern matches hl.on("event", function() body end)
    -- %b() matches balanced parentheses for the function body
    if vim.startswith(chunk, "hl.on") then
      local event, body = chunk:match('^hl%.on%("([^"]+)"%,%s*function%(%)%s*(.-)%s*end%)%s*$')

      if not event and body then
        error("could not parse hl.on chunk for optimization" .. chunk)
      end
      local indent1 = pretty.indent(1)

      -- Check if the previous chunk was also an hl.on for the same event
      local prev_event, prev_body
      local prev_chunk = optimized_chunks[#optimized_chunks]
      if prev_chunk then
        prev_event, prev_body =
          prev_chunk:match('^hl%.on%("([^"]+)"%,%s*function%(%)%s*(.-)%s*end%)%s*$')
      end

      if prev_event ~= event then
        optimized_chunks[#optimized_chunks + 1] = chunk
      else
        optimized_chunks[#optimized_chunks] = string.format(
          [[hl.on("%s", function()
%s%s
%s%s
end)]],
          event,
          indent1,
          prev_body,
          indent1,
          body
        )
      end
    else
      optimized_chunks[#optimized_chunks + 1] = chunk
    end
  end

  return optimized_chunks
end

return M
