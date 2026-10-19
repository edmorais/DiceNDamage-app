--[[
  app.lua -- the state every screen shares.

  One table, required by every module that draws or acts, so the tabs can
  hand work to each other without knowing how the others are drawn:

    st        the saved state (store.lua): the party, each character with its
              own presets and working attack, the situation, which tab and
              scheme are showing
    sol       the Calculator's solution for st, rebuilt when its inputs change
    views     each tray's last roll, animation and recent totals
    sheet     the preset sheet: open, which name is being typed
    party     the party sheet: open, its mode, the name being typed
    calc      the Calculator's scroll position and chart scrub
    toast     a short message at the bottom of the screen

  The test harnesses read and drive the app through this table too.
--]]

local palettes = require("palettes")

local app = {
  CALC = 1, ATTACK = 2, DAMAGE = 3, PERCENT = 4,
  st = nil,
  sol = nil, solSig = "",
  views = {},
  sheet = { open = false, editing = false, nameBuf = "", nameFresh = true, confirmDelete = 0 },
  party = { open = false, mode = "list", nameBuf = "", nameFresh = true, confirmDelete = 0, color = 1 },
  calc = { scroll = 0, contentH = 0, viewT = 0, viewB = 0, scrub = -1, plotX = 0, plotW = 1 },
  toast = nil, toastTime = 0,
  clock = 0,                       -- seconds since launch, for the caret blink
  savedText = nil, saveIn = 0.6,
  storageError = nil,
}

--- Inclusive at both ends, as rolls.lua expects.
function app.rng(lo, hi)
  return love.math.random(lo, hi)
end

--- A float in [0, x), for the animation's jitter.
function app.random(x)
  return love.math.random() * x
end

function app.pal()
  return palettes[app.st.palIdx]
end

function app.say(s)
  app.toast = s
  app.toastTime = 2.4
end

return app
