--[[
  hooks.lua -- the one seam the test harnesses use.

  test/render.lua, test/tapmap.lua and test/fuzz.lua copy the game and
  replace this file with a driver. In the shipped game every hook does
  nothing.

    load()        once, after the session is read
    update(dt)    at the start of every update, before anything moves
    frame()       at the end of every draw, after the frame is complete
    note(id, a)   every action and every stepper step, so the click-through
                  test can check that a tap did what the control says, not
                  only that it landed
--]]

local hooks = {}

function hooks.load() end
function hooks.update(dt) end
function hooks.frame() end
function hooks.note(id, arg) end

return hooks
