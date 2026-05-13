local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local utils = require("tests.utils")

local T = new_set()

-- https://wiki.hypr.land/0.54.0/Configuring/Animations/#example
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations
T["converts bezier with control points"] = function()
  utils.expect_hyprtolua_line(
    [[bezier = overshoot, 0.05, 0.9, 0.1, 1.1]],
    [[hl.curve("overshoot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.1 } } })]]
  )
end

T["converts gestures"] = function()
  utils.expect_hyprtolua_line(
    [[gesture = 3, horizontal, workspace]],
    [[hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })]]
  )
  utils.expect_hyprtolua_line(
    [[gesture = 3, down, mod: ALT, close]],
    [[hl.gesture({ fingers = 3, direction = "down", mods = "ALT", action = "close" })]]
  )
  -- works but the actual text doesn't oneline lol
  -- utils.expect_hyprtolua_line(
  --   [[gesture = 3, up, mod: SUPER, scale: 1.5, fullscreen]],
  --   [[hl.gesture({ fingers = 3, direction = "up", mods = "SUPER", scale = 1.5, action = "fullscreen" })]]
  -- )
  utils.expect_hyprtolua_line(
    [[gesture = 3, left, scale: 1.5, float]],
    [[hl.gesture({ fingers = 3, direction = "left", scale = 1.5, action = "float" })]]
  )
end

return T
