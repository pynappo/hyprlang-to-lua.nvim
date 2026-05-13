local pretty = require("hyprlang-to-lua.luagen.pretty")
local utils = require("hyprlang-to-lua.utils")
local toluacode = pretty.toluacode

---A module holding code to convert dispatchers to luacode
local M = {}
---@alias hyprtolua.luagen.DispatchConverterFunction fun(params: string[], params_raw: string):luacode:string
---@type hyprtolua.luagen.DispatchConverterFunction
local exec_to_luacode = function(_, params_raw)
  -- 1. Use a pattern to find content inside brackets: %[(.-)%]
  --    %[ and %] escape the brackets
  --    (.-) non-greedily captures everything inside
  local rules_str = assert(params_raw):match("^%s*%[(.-)%]")

  if rules_str then
    local rule_parts = {}
    for rule_str in vim.gsplit(rules_str, ";", { plain = true }) do
      local parts = vim.split(rule_str, " ", { plain = true })
      assert(#parts > 0, "expected rule to contain more than one word, rules_str:" .. rules_str)
      if #parts == 1 then
        rule_parts[#rule_parts + 1] = { [parts[1]] = true }
      else
        rule_parts[#rule_parts + 1] = { [parts[1]] = table.concat(parts, " ", 2) }
      end
    end
    return ("hl.dsp.exec_cmd(%s, %s)"):format(
      toluacode(params_raw),
      pretty.merge_toluacode(rule_parts)
    )
  end

  return ("hl.dsp.exec_cmd(%s)"):format(toluacode(params_raw))
end

---@param s string
---@return boolean? relative
---@return number|string x
---@return number|string y
local parse_resizeparams = function(s)
  local parts = vim.split(s, "%s+")
  local exact, x, y
  if #parts == 3 then
    exact, x, y = unpack(parts)
    assert(exact == "exact")
  elseif #parts == 2 then
    x, y = unpack(parts)
  end
  x = tonumber(x) or x
  y = tonumber(y) or y
  return not exact, x, y
end

---Converts old hyprlang window special strings to lua equivalent
---@param window_value string?
---@return string?
local winval = function(window_value)
  if window_value == "active" then
    return "activewindow"
  end
  return window_value
end

local directions = {
  "l",
  "r",
  "u",
  "d",
}
local function isdirection(s)
  return vim.tbl_contains(directions, s)
end

local lock_actions_to_actions = {
  lock = "enable",
  unlock = "disable",
  toggle = "toggle",
}

local noequivalent = function(dispatcher)
  return ("function() --[[hyprlang-to-lua: no equivalent for %s]] end"):format(dispatcher)
end

---@type table<string, string|hyprtolua.luagen.DispatchConverterFunction|false>
local dispatcher_converters = {
  exec = exec_to_luacode,
  execr = exec_to_luacode,
  -- pass	passes the key (with mods) to a specified window. Can be used as a workaround to global keybinds not working on Wayland.	window
  pass = function(params)
    local window = unpack(params)
    return ("hl.dsp.pass(%s)"):format(toluacode({ window = window }))
  end,
  -- sendshortcut	sends specified keys (with mods) to an optionally specified window. Can be used like pass	mod, key[, window]
  sendshortcut = function(params)
    local mod, key, window = unpack(params)
    return ("hl.dsp.send_shortcut(%s)"):format(pretty.tbl_toluacode({
      mods = mod,
      key = key,
      window = winval(window),
    }, { "mods", "key", "window" }))
  end,
  -- sendkeystate	Send a key with specific state (down/repeat/up) to a specified window (window must keep focus for events to continue).	mod, key, state, window
  sendkeystate = function(params)
    local mod, key, state, window = unpack(params)
    return ("hl.dsp.send_shortcut(%s)"):format({
      mods = mod,
      key = key,
      state = state,
      window = winval(window),
    })
  end,
  -- killactive	closes (not kills) the active window	none
  killactive = function()
    return ("hl.dsp.window.close(%s)"):format(toluacode({ window = "activewindow" }))
  end,
  -- forcekillactive	kills the active window	none
  forcekillactive = function()
    return ("hl.dsp.window.kill(%s)"):format(toluacode({ window = "activewindow" }))
  end,
  -- closewindow	closes a specified window	window
  closewindow = function(params)
    local window = unpack(params)
    return ("hl.dsp.window.close(%s)"):format(toluacode({ window = winval(window) }))
  end,
  -- killwindow	kills a specified window	window
  killwindow = function(params)
    local window = unpack(params)
    return ("hl.dsp.window.kill(%s)"):format(toluacode({ window = winval(window) }))
  end,
  -- signal	sends a signal to the active window	signal
  signal = function(params)
    local signal = unpack(params)
    return ("hl.dsp.window.signal(%s)"):format(toluacode({ signal = signal }))
  end,
  -- signalwindow	sends a signal to a specified window	window,signal, e.g.class:Alacritty,9
  signalwindow = function(params)
    local window, signal = unpack(params)
    return ("hl.dsp.window.signal(%s)"):format(
      pretty.tbl_toluacode({ window = winval(window), signal = signal }, { "window", "signal" })
    )
  end,
  -- workspace	changes the workspace	workspace
  workspace = function(params)
    local workspace = unpack(params)
    return ("hl.dsp.focus(%s)"):format(toluacode({ workspace = workspace }))
  end,
  -- movetoworkspace	moves the focused window to a workspace	workspace OR workspace,window for a specific window
  movetoworkspace = function(params)
    local workspace, window = unpack(params)
    return ("hl.dsp.window.move(%s)"):format(pretty.tbl_toluacode({
      workspace = workspace,
      window = winval(window),
    }, { "workspace", "window" }))
  end,
  -- movetoworkspacesilent	same as above, but doesn’t switch to the workspace	workspace OR workspace,window for a specific window
  movetoworkspacesilent = function(params)
    local workspace, window = unpack(params)
    return ("hl.dsp.window.move(%s)"):format(pretty.tbl_toluacode({
      workspace = workspace,
      window = winval(window),
      follow = false,
    }, { "workspace", "window" }))
  end,
  -- togglefloating	toggles the current window’s floating state	left empty / active for current, or window for a specific window
  togglefloating = function(params)
    local window = unpack(params)
    return ("hl.dsp.window.float(%s)"):format(pretty.tbl_toluacode({
      window = winval(window),
      action = "toggle",
    }, { "window", "action" }))
  end,
  -- setfloating	sets the current window’s floating state to true	left empty / active for current, or window for a specific window
  setfloating = function(params)
    local window = unpack(params)
    return ("hl.dsp.window.float(%s)"):format(pretty.tbl_toluacode({
      window = winval(window),
      action = "on",
    }, { "window", "action" }))
  end,
  -- settiled	sets the current window’s floating state to false	left empty / active for current, or window for a specific window
  settiled = function(params)
    local window = unpack(params)
    return ("hl.dsp.window.float(%s)"):format(pretty.tbl_toluacode({
      window = winval(window),
      action = "off",
    }, { "window", "action" }))
  end,
  -- fullscreen	sets the focused window’s fullscreen mode	mode action, where mode can be 0 - fullscreen (takes your
  -- entire screen) or 1 - maximize (keeps gaps and bar(s)), while action is optional and can be toggle (default), set
  -- or unset.
  fullscreen = function(params)
    local mode_action = unpack(params)
    ---@type string?, string?
    local mode_str, action = unpack(vim.split(mode_action, "%s+"))

    return ("hl.dsp.window.fullscreen(%s)"):format(pretty.tbl_toluacode({
      mode = mode_str and tonumber(mode_str) or 0,
      action = utils.istruthy(action) and action or nil,
    }, { "mode", "action" }))
  end,
  -- fullscreenstate	sets the focused window’s fullscreen mode and the one sent to the client	internal client
  -- action, where internal (the hyprland window) and client (the application) can be -1 - current, 0 - none, 1 -
  -- maximize, 2 - fullscreen, 3 - maximize and fullscreen. action is optional and can be toggle (default) or set.
  fullscreenstate = function(params)
    local internal_client_action = unpack(params)
    local internal_str, client_str, fullscreenstate_action =
      utils.unpack_by_whitespace(internal_client_action)
    local action
    if fullscreenstate_action == "set" then
      action = "enable"
    elseif fullscreenstate_action == "toggle" then
      action = "toggle"
    end

    return ("hl.dsp.window.fullscreen_state(%s)"):format(pretty.tbl_toluacode({
      internal = assert(tonumber(internal_str)),
      client = assert(tonumber(client_str)),
      action = action,
    }, {
      "internal",
      "client",
      "action",
    }))
  end,
  -- dpms	sets all monitors’ DPMS status. Do not use with a keybind directly.	on, off, or toggle. For specific monitor
  -- add monitor name after a space
  dpms = function(params)
    local action_monitor = unpack(params)
    local action, monitor = unpack(vim.split(action_monitor, " ", { plain = true }))
    return ("hl.dsp.dpms(%s)"):format({
      action = action,
      monitor = monitor,
    })
  end,
  -- forceidle	sets elapsed time for all idle timers, ignoring idle inhibitors. Timers return to normal behavior upon
  -- the next activity. Do not use with a keybind directly.	floatvalue (number of seconds)
  forceidle = function(params)
    local seconds_str = unpack(params)
    local seconds = tonumber(seconds_str)
    return ("hl.dsp.force_idle(%s)"):format(seconds)
  end,
  -- pin	pins a window (i.e. show it on all workspaces) note: floating only	left empty / active for current, or
  -- window for a specific window
  pin = function(params)
    local window = unpack(params)
    return ("hl.dsp.window.pin(%s)"):format(toluacode({
      window = winval(window),
    }))
  end,
  -- movefocus	moves the focus in a direction	direction
  movefocus = function(params)
    local direction = unpack(params)
    return ("hl.dsp.focus(%s)"):format(toluacode({
      direction = direction,
    }))
  end,
  -- movewindow	moves the active window in a direction or to a monitor. For floating windows, moves the window to the
  -- screen edge in that direction	direction or mon: and a monitor, optionally followed by a space and silent to
  -- prevent the focus from moving with the window
  movewindow = function(params)
    local direction_or_monitor = unpack(params)
    if isdirection(direction_or_monitor) then
      return ("hl.dsp.window.move(%s)"):format(toluacode({
        direction = direction_or_monitor,
      }))
    else
      local monitor = direction_or_monitor:sub(5)
      local follow = nil
      if vim.endswith(monitor, " silent") then
        follow = false
      end
      return ("hl.dsp.window.move(%s)"):format(pretty.tbl_toluacode({
        monitor = monitor,
        follow = follow,
      }, { "monitor", "follow" }))
    end
  end,
  -- swapwindow	swaps the active window with another window in the given direction or with a specific window
  -- direction or window
  swapwindow = function(params)
    local direction_or_window = unpack(params)
    if isdirection(direction_or_window) then
      return ("hl.dsp.window.swap(%s)"):format(toluacode({
        direction = direction_or_window,
      }))
    else
      return ("hl.dsp.window.swap(%s)"):format(toluacode({
        target = winval(direction_or_window),
      }))
    end
  end,
  -- centerwindow	center the active window note: floating only	none (for monitor center) or 1 (to respect monitor reserved area)
  centerwindow = "hl.dsp.window.center()",
  -- resizeactive	resizes the active window	resizeparams
  resizeactive = function(params)
    local resizeparams_str = unpack(params)
    local relative, x, y = parse_resizeparams(resizeparams_str)
    return ("hl.dsp.window.resize(%s)"):format(pretty.tbl_toluacode({
      x = x,
      y = y,
      relative = relative,
      window = "activewindow",
    }, { "x", "y", "relative", "window" }))
  end,
  -- moveactive	moves the active window	resizeparams
  moveactive = function(params)
    local resizeparams_str = unpack(params)
    local relative, x, y = parse_resizeparams(resizeparams_str)
    return ("hl.dsp.window.move(%s)"):format(pretty.tbl_toluacode({
      x = x,
      y = y,
      relative = relative,
    }, { "x", "y", "relative", "window" }))
  end,
  -- resizewindowpixel	resizes a selected window	resizeparams,window, e.g. 100 100,^(kitty)$
  resizewindowpixel = function(params)
    local resizeparams_str, window = unpack(params)
    local relative, x, y = parse_resizeparams(resizeparams_str)
    return ("hl.dsp.window.resize(%s)"):format(pretty.tbl_toluacode({
      x = x,
      y = y,
      relative = relative,
      window = "activewindow",
    }, { "x", "y", "relative", "window" }))
  end,
  -- movewindowpixel	moves a selected window	resizeparams,window
  movewindowpixel = function(params)
    local resizeparams_str, window = unpack(params)
    local relative, x, y = parse_resizeparams(resizeparams_str)
    return ("hl.dsp.window.move(%s)"):format(pretty.tbl_toluacode({
      x = x,
      y = y,
      relative = relative,
      window = window,
    }, { "x", "y", "relative", "window" }))
  end,
  -- cyclenext	focuses the next window (on a workspace, if visible is not provided)	none (for next) or prev (for
  -- previous) additionally tiled for only tiled, floating for only floating. prev tiled is ok. visible for all
  -- monitors cycling. visible prev floating is ok. if hist arg provided - focus order will depends on focus history.
  -- All other modifiers is also working for it, visible next floating hist is ok.
  cyclenext = function(params)
    local modifiers_str = unpack(params)
    local modifiers = vim.split(modifiers_str, " ", { plain = true })
    local next, tiled, floating, window
    if vim.tbl_contains(modifiers, "prev") then
      next = false
    elseif vim.tbl_contains(modifiers, "next") then
      next = true
    end
    return ("hl.dsp.window.cycle_next(%s)"):format(pretty.tbl_toluacode({
      next = next,
      tiled = tiled,
      floating = floating,
    }, { "next", "tiled", "floating" }))
  end,
  -- swapnext	swaps the focused window with the next window on a workspace	none (for next) or prev (for previous)
  swapnext = function(params)
    if params[1] == "prev" then
      return ("hl.dsp.window.swap(%s)"):format(toluacode({
        prev = true,
      }))
    else
      return ("hl.dsp.window.swap(%s)"):format(toluacode({
        next = true,
      }))
    end
  end,
  -- tagwindow	apply tag to current or the first window matching	tag [window], e.g. +code ^(foot)$, music
  tagwindow = function(params)
    local tag, window = unpack(params)
    return ("hl.dsp.window.tag(%s)"):format(pretty.tbl_toluacode({
      tag = tag,
      window = window,
    }, { "tag", "window" }))
  end,
  focuswindow = function(params)
    -- focuswindow	focuses the first window matching	window
    local window = unpack(params)
    return ("hl.dsp.focus(%s)"):format(toluacode({
      window = window,
    }))
  end,
  -- focusmonitor	focuses a monitor	monitor
  focusmonitor = function(params)
    local monitor = unpack(params)
    return ("hl.dsp.focus(%s)"):format(toluacode({
      monitor = monitor,
    }))
  end,
  -- movecursortocorner	moves the cursor to the corner of the active window	direction, 0 - 3, bottom left - 0, bottom
  -- right - 1, top right - 2, top left - 3
  movecursortocorner = function(params)
    local corner_str = unpack(params)
    local corner = assert(tonumber(corner_str))
    return ("hl.dsp.corner.move_to_corner(%s)"):format(toluacode({
      corner = corner,
    }))
  end,
  -- movecursor	moves the cursor to a specified position	x y
  movecursor = function(params)
    local x_y = unpack(params)
    local x_str, y_str = unpack(vim.split(x_y, "%s+"))
    local x, y = tonumber(x_str), tonumber(y_str)
    return ("hl.dsp.cursor.move(%s)"):format(pretty.tbl_toluacode({
      x = x,
      y = y,
    }, { "x", "y" }))
  end,
  -- renameworkspace	rename a workspace	id name, e.g. 2 work
  renameworkspace = function(params)
    local id_name = unpack(params)
    local id, name = unpack(vim.split(id_name, "%s+"))
    return ("hl.dsp.workspace.rename(%s)"):format(pretty.tbl_toluacode({
      workspace = id,
      name = name,
    }, { "workspace", "name" }))
  end,
  -- exit	exits the compositor with no questions asked. It’s recommended to use hyprshutdown instead of this.	none
  exit = "hl.dsp.exit()",
  -- forcerendererreload	forces the renderer to reload all resources and outputs	none
  forcerendererreload = noequivalent("forcerendererreload"),
  -- movecurrentworkspacetomonitor	Moves the active workspace to a monitor	monitor
  movecurrentworkspacetomonitor = function(params)
    local monitor = unpack(params)
    return ("hl.dsp.workspace.move(%s)"):format(toluacode({
      monitor = monitor,
    }))
  end,
  -- focusworkspaceoncurrentmonitor	Focuses the requested workspace on the current monitor, swapping the current
  -- workspace to a different monitor if necessary. If you want XMonad/Qtile-style workspace switching, replace
  -- workspace in your config with this.	workspace
  focusworkspaceoncurrentmonitor = function(params)
    local workspace = unpack(params)
    return ("hl.dsp.focus(%s)"):format(pretty.tbl_toluacode({
      workspace = workspace,
      on_current_monitor = true,
    }, { "workspace", "on_current_monitor" }))
  end,
  -- moveworkspacetomonitor	Moves a workspace to a monitor	workspace and a monitor separated by a space
  moveworkspacetomonitor = function(params)
    local workspace_monitor = unpack(params)
    local workspace, monitor = utils.unpack_by_whitespace(workspace_monitor)
    return ("hl.dsp.workspace.move(%s)"):format(pretty.tbl_toluacode({
      workspace = workspace,
      monitor = monitor,
    }, { "workspace", "monitor" }))
  end,
  -- swapactiveworkspaces	Swaps the active workspaces between two monitors	two monitors separated by a space
  swapactiveworkspaces = function(params)
    local monitor1_2 = unpack(params)
    local monitor1, monitor2 = utils.unpack_by_whitespace(monitor1_2)
    return ("hl.dsp.workspace.swap_monitors(%s)"):format(pretty.tbl_toluacode({
      monitor1 = monitor1,
      monitor2 = monitor2,
    }, { "monitor1", "monitor2" }))
  end,
  -- bringactivetotop	Deprecated in favor of alterzorder. Brings the current window to the top of the stack	none
  bringactivetotop = function()
    return ("hl.dsp.window.alter_zorder(%s)"):format(toluacode({
      mode = "top",
    }))
  end,
  -- alterzorder	Modify the window stack order of the active or specified window. Note: this cannot be used to move a
  -- floating window behind a tiled one.	zheight[,window]
  alterzorder = function(params)
    local zheight, window = unpack(params)
    return ("hl.dsp.window.alter_zorder(%s)"):format(pretty.tbl_toluacode({
      mode = zheight,
      window = winval(window),
    }, { "mode", "window" }))
  end,
  togglespecialworkspace = function(params)
    -- togglespecialworkspace	toggles a special workspace on/off	none (for the first) or name for named (name has to be
    -- a special workspace’s name)
    local name = unpack(params)
    return ("hl.dsp.workspace.toggle_special(%s)"):format(toluacode(name))
  end,
  focusurgentorlast = "hl.dsp.focus({ urgent_or_last = true })",
  -- togglegroup	toggles the current active window into a group	none
  togglegroup = "hl.dsp.group.toggle()",
  -- changegroupactive	switches to the next window in a group.	b - back, f - forward, or index start at 1
  changegroupactive = function(params)
    local next_window = unpack(params)
    if next_window == "b" then
      return "hl.dsp.group.prev()"
    end
    if next_window == "f" then
      return "hl.dsp.group.next()"
    end
    local nextwindow_index = tonumber(next_window)
    if tonumber(next_window) then
      return ("hl.dsp.group.active(%s)"):format(toluacode({
        index = nextwindow_index,
      }))
    end
    error(("Could not handle changegroupactive parameter: %s"):format(next_window))
  end,
  -- focuscurrentorlast	Switch focus from current to previously focused window	none
  focuscurrentorlast = "hl.dsp.focus({ last = true })",
  -- lockgroups	Locks the groups (all groups will not accept new windows)	lock for locking, unlock for unlocking,
  -- toggle for toggle
  lockgroups = function(params)
    local lock_action = unpack(params)
    local action = lock_actions_to_actions[lock_action]
    if action then
      return ("hl.dsp.group.lock(%s)"):format(toluacode({
        action = action,
      }))
    else
      return "hl.dsp.group.lock()"
    end
  end,
  -- lockactivegroup	Lock the focused group (the current group will not accept new windows or be moved to other
  -- groups)	lock for locking, unlock for unlocking, toggle for toggle
  lockactivegroups = function(params)
    local lock_action = unpack(params)
    local action = lock_actions_to_actions[lock_action]
    if action then
      return ("hl.dsp.group.lock_active(%s)"):format(toluacode({
        action = action,
      }))
    else
      return "hl.dsp.group.lock_active()"
    end
  end,
  -- moveintogroup	Moves the active window into a group in a specified direction. No-op if there is no group in the
  -- specified direction.	direction
  moveintogroup = function(params)
    local direction = unpack(params)
    return ("hl.dsp.window.move(%s)"):format(toluacode({
      into_group = direction,
    }))
  end,
  -- moveoutofgroup	Moves the active window out of a group. No-op if not in a group	left empty / active for current,
  -- or window for a specific window
  moveoutofgroup = function(params)
    local direction = unpack(params)
    return ("hl.dsp.window.move(%s)"):format(toluacode({
      out_of_group = direction,
    }))
  end,
  -- movewindoworgroup	Behaves as moveintogroup if there is a group in the given direction. Behaves as moveoutofgroup
  -- if there is no group in the given direction relative to the active group. Otherwise behaves like movewindow.
  -- direction
  movewindoworgroup = function(params)
    local direction = unpack(params)
    -- based off of guessing from hyprland's lua bindings code, not sure if this is correct
    return ("hl.dsp.window.move(%s)"):format(pretty.tbl_toluacode({
      direction = direction,
      group_aware = true,
    }, { "direction", "group_aware" }))
  end,
  -- movegroupwindow	Swaps the active window with the next or previous in a group	b for back, anything else for
  -- forward
  movegroupwindow = function(params)
    local b = unpack(params)
    if b == "b" then
      return ("hl.dsp.group.move_window(%s)"):format(toluacode({
        forward = false,
      }))
    end
    return ("hl.dsp.group.move_window(%s)"):format(toluacode({
      forward = true,
    }))
  end,
  -- denywindowfromgroup	Prohibit the active window from becoming or being inserted into group	on, off or, toggle
  denywindowfromgroup = function(params)
    local action = unpack(params)
    return ("hl.dsp.window.deny_from_group(%s)"):format(toluacode({
      action = action,
    }))
  end,
  -- setignoregrouplock	Temporarily enable or disable binds:ignore_group_lock	on, off, or toggle
  setignoregrouplock = noequivalent("setignoregrouplock"),
  -- global	Executes a Global Shortcut using the GlobalShortcuts portal. See here	name
  global = function(params)
    local name = unpack(params)
    return ("hl.dsp.global(%s)"):format(toluacode(name))
  end,
  -- submap	Change the current mapping group. See Submaps	reset or name
  submap = function(params)
    local name = unpack(params)
    return ("hl.dsp.submap(%s)"):format(toluacode(name))
  end,
  -- event	Emits a custom event to socket2 in the form of custom>>yourdata	the data to send
  event = function(params)
    local data = unpack(params)
    return ("hl.dsp.event(%s)"):format(toluacode(data))
  end,
  -- setprop	Sets a window property	window property value
  setprop = function(params)
    local win_prop_value = unpack(params)
    local window, property, value = utils.unpack_by_whitespace(win_prop_value)
    return ("hl.dsp.window.set_prop(%s)"):format(pretty.tbl_toluacode({
      prop = property,
      value = value,
      window = window,
    }, { "property", "value", "window" }))
  end,
  -- toggleswallow
  toggleswallow = "hl.dsp.window.toggle_swallow()",
  -- dwindle stuff
  pseudo = "hl.dsp.window.pseudo()",
  layoutmsg = function(_, params_raw)
    return ("hl.dsp.layout(%s)"):format(params_raw)
  end,
}

---@type table<string, string|hyprtolua.luagen.DispatchConverterFunction|false>
local mouse_dispatcher_converters = {
  movewindow = "hl.dsp.window.drag()",
  resizewindow = "hl.dsp.window.resize()",
}

---@param dispatcher string
---@param params_raw string
---@param is_mouse_dispatcher boolean
---@return string? luacode
M.dispatcher_toluacode = function(dispatcher, params_raw, is_mouse_dispatcher)
  local converter
  if is_mouse_dispatcher then
    converter = mouse_dispatcher_converters[dispatcher] or dispatcher_converters[dispatcher]
  end
  converter = converter or dispatcher_converters[dispatcher]
  if not converter then
    error(
      ("Dispatcher convertion not implemented for dispatcher %s, params: %s"):format(
        dispatcher,
        params_raw
      )
    )
  end
  local converter_type = type(converter)
  if converter_type == "function" then
    local params = vim.split(params_raw, "%s*,%s*")
    return converter(params, params_raw)
  elseif converter_type == "string" then
    -- Already converted
    return converter
  end
  local errmsg = ("unimplemented dispatcher: %s, params_str: %s"):format(dispatcher, params_raw)
  error(errmsg)
  -- return ("-- hyprlang-to-lua dispatcher unimplemented: " .. errmsg)
end

return M
