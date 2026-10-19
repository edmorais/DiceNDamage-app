-- Window and module configuration for LOVE.
--
-- The window matches a phone in portrait. On Android the size is ignored and
-- the layout scales to whatever the device gives, so the numbers here only
-- decide what a desktop run looks like.

function love.conf(t)
  t.identity = "dnd-dice-and-damage"   -- save folder, holds session.txt
  t.version  = "11.4"

  t.window.title     = "Dice & Damage"
  t.window.width     = 390
  t.window.height    = 844
  t.window.minwidth  = 320
  t.window.minheight = 480
  t.window.resizable = true
  t.window.msaa      = 4
  t.window.highdpi   = true
  t.window.vsync     = 1

  t.modules.joystick = false
  t.modules.physics  = false
  t.modules.audio    = false
  t.modules.sound    = false
  t.modules.video    = false
end
