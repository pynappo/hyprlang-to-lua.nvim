local pretty = require("hyprlang-to-lua.luagen.pretty")
local utils = require("hyprlang-to-lua.utils")
local luagen_utils = require("hyprlang-to-lua.luagen.utils")
local migrate = require("hyprlang-to-lua.luagen.migrate")
local toluacode = pretty.toluacode
local Generator = {}

---Creates a new generator instance
---@class hyprtolua.LuaGenerator
---@field chunks string[] The chunks processed so far
---@field variables string[] The chunks processed so far
function Generator:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self

  o.chunks = {}
  return o
end

---@param irs hyprtolua.ir.Exec[]
---@param variant hyprtolua.ir.ExecVariant
---@return string luacode
---@nodiscard
function Generator:exec_toluacode(irs, variant)
  ---@type string[]
  local exec_cmd_lines = {}
  for _, ir in ipairs(irs) do
    ---@type HL.WindowRuleSpec
    if ir.rules then
      local window_rule_spec = {}
      local keyorder = {}
      for _, rule in ipairs(ir.rules) do
        keyorder[#keyorder + 1] = rule.name
        if #rule.arguments == 0 then
          window_rule_spec[rule.name] = true
        else
          window_rule_spec[rule.name] = table.concat(rule.arguments, " ")
        end
      end
      migrate.window_rule(window_rule_spec)
      exec_cmd_lines[#exec_cmd_lines + 1] = ("%shl.exec_cmd(%s, %s)"):format(
        pretty.indent(1),
        toluacode(ir.command),
        pretty.tbl_toluacode(window_rule_spec, keyorder)
      )
    else
      exec_cmd_lines[#exec_cmd_lines + 1] = ("%shl.exec_cmd(%s)"):format(
        pretty.indent(1),
        toluacode(ir.command)
      )
    end
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
function Generator:config_toluachunks(config_ir)
  ---@type string[]
  self.chunks = {}
  ---@type table<string, hyprtolua.ir.DeclarationValue>
  self.variables = {}
  ---@type table<string, string>
  self.old_varnames = {}
  local chunks = self.chunks
  ---@type string?
  local submap = nil
  for i = 1, #config_ir do
    local ir = config_ir[i]
    local chunk = ""
    if ir.command then
      local execs_of_same_variant = { ir }
      ---@cast ir hyprtolua.ir.Exec
      while i < #ir and ir[i + 1].variant == ir.variant do
        table.insert(execs_of_same_variant, ir[i + 1])
        i = i + 1
      end
      chunk = self:exec_toluacode(execs_of_same_variant, ir.variant)
    elseif ir.comment then
      ---@cast ir hyprtolua.ir.Comment
      chunk = "--" .. ir.comment
    elseif ir.params then
      ---@cast ir hyprtolua.ir.Keyword
      if ir.keyword == "submap" then
        submap, chunk = parse_submap(ir, submap)
      else
        chunk = self:keyword_toluacode(ir)
        if submap then
          chunk = pretty.add_indent(chunk, 1)
        end
      end
    elseif ir.section_name then
      ---@cast ir hyprtolua.ir.Section
      chunk = self:section_toluacode(ir)
    elseif ir.source then
      local path_to_source = vim.fs.normalize(ir.source)
      local require_path
      if vim.startswith(path_to_source, utils.config_hypr_path .. "/") then
        local path_from_config_dir = path_to_source:sub(#utils.config_hypr_path + 2)
        require_path = path_from_config_dir:gsub("/", "."):gsub("%.conf$", "")
      end
      if require_path then
        chunk = ("require(%s)"):format(toluacode(require_path))
      else
        chunk = ("-- require(%s) -- hyprlang-to-lua: could not convert this path to require() equivalent"):format(
          toluacode(ir.source)
        )
      end
    elseif ir.declared_name then
      ---@cast ir hyprtolua.ir.Declaration
      local varname, value = migrate.variable_name(ir.declared_name), ir.value
      self.old_varnames[ir.declared_name] = varname
      if not self.variables[varname] then
        chunk = ("local %s = %s"):format(varname, toluacode(value))
      else
        chunk = ("%s = %s"):format(varname, toluacode(value))
      end
      self.variables[varname] = ir.value
    end
    if not chunk then
      error("Unhandled ir in config: " .. vim.inspect(ir))
    end
    chunks[#chunks + 1] = chunk
  end
  if submap then
    chunks[#chunks + 1] = "end)"
  end
  return chunks
end

---@param t table
---@param keys any[]k
---@param value any
---@return any previous
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
  local last_key = keys[#keys]
  local prev = node[last_key]
  node[last_key] = value
  return prev
end

---@param section_ir hyprtolua.ir.Section
---@return table section
---@return any[] section_keyorder
function Generator:_section_to_tbl_and_keys(section_ir)
  local tbl = {}
  local section_keyorder = {}
  for _, ir in ipairs(section_ir) do
    local keys = {}
    local v
    if ir.section_name then
      ---@cast ir hyprtolua.ir.Section
      vim.list_extend(keys, { ir.section_name, ir.device })
      v, _ = self:_section_to_tbl_and_keys(ir)
    elseif ir.keyword then
      ---@cast ir hyprtolua.ir.Keyword
      vim.list_extend(keys, vim.split(ir.keyword, "[:%.]"))
      if #ir.params == 1 then
        v = ir.params[1]
      elseif #ir.params > 1 then
        v = { unpack(ir.params) }
      else
        v = ir.params.raw
      end
    else
      error("TODO: unparsed ir in section: " .. pretty.toluacode(ir))
    end

    keys = vim.iter(keys):map(utils.tosnakecase):totable()

    local prev = tbl_set(tbl, keys, v)
    if prev ~= nil and prev ~= v then
      self.chunks[#self.chunks + 1] = ("-- hyprlang-to-lua: excluding %s = %s from below, as Lua does not allow duplicate keys"):format(
        table.concat(keys, "."),
        prev
      )
    end
    section_keyorder[#section_keyorder + 1] = keys[1]
  end
  return tbl, section_keyorder
end

---@param ir hyprtolua.ir.Section
---@nodiscard
function Generator:section_toluacode(ir)
  if ir.section_name == "monitorv2" then
    ---@type HL.MonitorSpec
    local monitor_opts, keys = self:_section_to_tbl_and_keys(ir)
    if monitor_opts.scale then
      -- Convert to a string
      monitor_opts.scale = tostring(monitor_opts.scale)
    end
    return ([[hl.monitor(%s)]]):format(pretty.tbl_toluacode(monitor_opts, keys))
  elseif ir.section_name == "windowrule" then
    local window_rule_spec, keys = self:_section_to_tbl_and_keys(ir)
    migrate.window_rule(window_rule_spec)
    return ([[hl.window_rule(%s)]]):format(pretty.tbl_toluacode(window_rule_spec, keys))
  end
  local indent1 = pretty.indent(1)
  local config, keys = self:_section_to_tbl_and_keys(ir)
  return ([[
hl.config({
%s%s = %s
})]]):format(
    indent1,
    pretty.tokeystring(ir.section_name),
    pretty.tbl_toluacode(config, keys, indent1, -1)
  )
end

---Parses a parameter into a value and potentially its key:
---key:val, key val, or subkey1:subkey2 val
---If the parameter matches none of the above formats, returns the string itself.
---@param param_str string
---@return string val
---@return string[]? keys
function Generator:_param_string_to_val(param_str)
  local space_idx = param_str:find(" ", 1, true)
  if not space_idx then
    if not param_str:find(":") then
      -- val
      return param_str
    end
    -- key:val
    local key, value = unpack(vim.split(param_str, ":", { plain = true, trimempty = true }))
    return value, { key }
  end

  local key, value = param_str:sub(1, space_idx - 1), param_str:sub(space_idx + 1)

  -- subkey1:subkey2 val or key val
  return value, vim.split(key, ":", { plain = true })
end

---Takes a table and merges in parameters from (start or 1) until (j or #params)
---@param tbl table
---@param params hyprtolua.ir.Params
---@param i integer?
---@param j integer?
---@return any[] keys
---@return any[] unmerged_values
function Generator:_merge_params(tbl, params, i, j)
  local keys_by_param_order = {}
  local unmerged = {}
  for idx = i or 1, j or #params do
    local param = params[idx]
    if type(param) ~= "string" then
      unmerged[#unmerged + 1] = param
    else
      local val, keys = self:_param_string_to_val(param)
      if not keys then
        unmerged[#unmerged + 1] = val
      else
        vim.iter(keys):map(utils.tosnakecase):totable()
        keys_by_param_order[#keys_by_param_order + 1] = keys
        local prev = tbl_set(tbl, keys, val)
        if prev ~= nil then
          self.chunks[#self.chunks + 1] = ("-- hyprlang-to-lua: excluding %s = %s from below, as Lua does not allow duplicate keys"):format(
            table.concat(keys, "."),
            prev
          )
        end
      end
    end
  end
  return keys_by_param_order, unmerged
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
function Generator:keyword_toluacode(ir)
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
    local keys_by_merge_order = self:_merge_params(ws_rule, ir.params, 2)
    migrate.workspace_rule(ws_rule, keys_by_merge_order)
    return ("hl.workspace_rule(%s)"):format(
      pretty.tbl_toluacode(ws_rule, vim.list_extend({ "workspace" }, keys_by_merge_order))
    )
  elseif keyword == "windowrule" then
    ---@type HL.WindowRuleSpec
    local window_rule_spec = {}
    local keys = self:_merge_params(window_rule_spec, ir.params)

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
      ---@type string, string, string, string, string
      modstring, key, desc, dispatcher, dispatcher_params =
        raw_params:match("^([^,]*),%s*([^,]*),%s*([^,]+),%s*([^,]+)%s*,?%s*(.*)")
      bind_opts.desc = desc
    else
      ---mods, key, desc, dispatcher(, params)
      ---@type string, string, string, string
      modstring, key, dispatcher, dispatcher_params =
        raw_params:match("^([^,]*),%s*([^,]*),%s*([^,]+)%s*,?%s*(.*)")
    end

    local lhs_code = migrate.bind_lhs_code(modstring, key)

    local dispatcher_code = require("hyprlang-to-lua.luagen.dispatchers").dispatcher_toluacode(
      dispatcher,
      dispatcher_params,
      lhs_code:find("mouse") ~= nil
    )

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
    local keys_by_merge_order = self:merge_params(layer_rule, ir.params)
    return ("hl.layer_rule(%s)"):format(pretty.tbl_toluacode(layer_rule, keys_by_merge_order))
  elseif keyword == "monitor" then
    local name, mode, position, scale = unpack(ir.params)
    ---@type HL.MonitorSpec
    local monitor_spec = {
      output = name,
      mode = mode,
      position = position,
      scale = scale,
    }
    return ("hl.monitor(%s)"):format(
      pretty.tbl_toluacode(monitor_spec, { "name", "mode", "position", "scale" })
    )
  elseif vim.startswith(ir.keyword, "gesture") then
    local fingers, direction, mods, scale, action

    local end_of_required_args = -1
    for i, param in ipairs(ir.params) do
      if not fingers then
        assert(type(param) == "number")
        fingers = param
      elseif not direction then
        assert(type(param) == "string")
        direction = param
      else
        assert(type(param) == "string")
        local val, keys = self:_param_string_to_val(param)
        if keys then
          local key = keys[1]
          if key == "mod" then
            mods = table.concat(migrate.find_mods(val), " + ")
          elseif key == "scale" then
            scale = tonumber(val)
          end
        else
          action = val
          end_of_required_args = i
        end
      end
    end

    ---@type HL.GestureSpec
    local gesture = {
      fingers = fingers,
      direction = direction,
      mods = mods,
      scale = scale,
      action = action,
    }

    if ir.keyword:find("p", 1, true) then
      gesture.disable_inhibit = true
    end

    if gesture.action == "dispatcher" then
      local dispatcher = assert(ir.params[end_of_required_args + 1])
      assert(
        type(dispatcher) == "string",
        "expected dispatcher in gesture after 'dispatcher' action"
      )
      local raw_dispatcher_params = table.concat(ir.params, ", ", end_of_required_args + 2)
      local dispatcher_code = require("hyprlang-to-lua.luagen.dispatchers").dispatcher_toluacode(
        dispatcher,
        raw_dispatcher_params,
        false
      )
      ---@diagnostic disable-next-line: assign-type-mismatch
      gesture.action =
        luagen_utils.wrap_raw_luacode(("function() hl.dispatch(%s) end"):format(dispatcher_code))
    else
      for i = end_of_required_args, #ir.params do
        local param = ir.params[i]
        assert(type(param) == "string")
        local v, keys = self:_param_string_to_val(param)
        if keys then
          local prev = tbl_set(gesture, keys, v)
          if prev ~= nil and prev ~= v then
            self.chunks[#self.chunks + 1] = ("-- hyprlang-to-lua: excluding %s = %s from below, as Lua does not allow duplicate keys"):format(
              table.concat(keys, "."),
              prev
            )
          end
        end
      end
    end

    return ("hl.gesture(%s)"):format(pretty.tbl_toluacode(gesture, {
      "fingers",
      "direction",
      "mods",
      "scale",
      "action",
    }))
  end
  error("TODO keyword:" .. toluacode(ir))
end
return Generator
