local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local utils = require("tests.utils")
local hyprtolua = require("hyprlang-to-lua")

local T = new_set()

-- https://wiki.hypr.land/0.54.0/Configuring/Animations/#example
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations
T["converts bezier with control points"] = function()
  utils.expect_hyprtolua_line(
    [[bezier = overshoot, 0.05, 0.9, 0.1, 1.1]],
    [[hl.curve("overshoot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.1 } } })]]
  )
end

T["converts animations"] = function()
  utils.expect_hyprtolua_line(
    [[animation = windows, 1, 8, default, popin 80%]],
    [[hl.animation({ leaf = "windows", enabled = true, speed = 8, curve = "default", style = "popin 80%" })]]
  )
  utils.expect_hyprtolua_line(
    [[animation = workspaces, 1, 8, default, slidefade 20%]],
    [[hl.animation({ leaf = "workspaces", enabled = true, speed = 8, curve = "default", style = "slidefade 20%" })]]
  )
  utils.expect_hyprtolua_line(
    [[animation = windows, 1, 8, default, slide left]],
    [[hl.animation({ leaf = "windows", enabled = true, speed = 8, curve = "default", style = "slide left" })]]
  )
end

return T
