#!/usr/bin/env python3
"""Render every interesting state of the game headlessly and save a PNG of
each, for visual review.

Copies game/, replaces hooks.lua with a driver that walks through the states
one frame at a time, sets the window size in conf.lua, and runs it with
`love` under Xvfb. Rolls use a scripted random source, so every screenshot is
reproducible. Stages go through app.activate wherever a control exists, so
each render is what a tap produces, not a state set behind the controls'
back.

    python3 test/render.py [WIDTHxHEIGHT] [outdir]
"""
import os
import shutil
import subprocess
import sys
import tempfile

TMP = os.path.join(tempfile.gettempdir(), "dice-and-damage-tests")

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), "game")

size = sys.argv[1] if len(sys.argv) > 1 else "1080x2400"
out = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else f"{TMP}/love-shots")
work = f"{TMP}/love-render/game"

shutil.rmtree(os.path.dirname(work), ignore_errors=True)
shutil.copytree(GAME, work)
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
w, h = (int(v) for v in size.split("x"))

DRIVER = r'''
local app = require("app")
local rules = require("rules")
local session = require("session")
local store = require("store")
local partysheet = require("partysheet")
local tray = require("tray")
local sheet = require("sheet")

io.stdout:setvbuf("no")
local hooks = {}
local OUT = "OUTDIR/"

-- A failure ends the run with the message instead of LOVE's error screen,
-- which would wait for a key forever under Xvfb.
function love.errorhandler(msg)
  print("ERROR: " .. debug.traceback(tostring(msg), 2))
  os.exit(1)
end

local function scripted(...)
  local script, at = { ... }, 0
  app.rng = function(lo, hi)
    at = at + 1
    local v = script[(at - 1) % #script + 1]
    return math.max(lo, math.min(hi, v))
  end
end

local function settleAll()
  for _, v in ipairs(tray.allViews()) do
    if v.d20Anim then v.d20Anim.t = v.d20Anim.revealAt + 0.6 end
    if v.dmgAnim then v.dmgAnim.t = v.dmgAnim.revealAt + 0.6 end
    v:advance(0)
  end
end

local names = {
  "01-calc-default", "02-calc-damage-vs-ac", "-add-a-row", "03-calc-controls",
  "04-attack-from-calc-crit", "05-damage-from-attack-crit", "06-attack-hit",
  "07-attack-fumble", "08-check", "09-damage-tab", "10-percent",
  "11-presets-from-damage", "12-presets-naming", "13-presets-delete-confirm",
  "14-calc-four-attacks", "15-scheme-2", "16-scheme-3", "17-scheme-4",
  "18-scheme-5", "19-scheme-6", "20-preset-saved", "21-attack-rolling",
  "22-insets-damage", "23-insets-sheet", "24-calc-scrub",
  "25-party", "26-party-new", "27-party-import", "28-switched-to-vex", "29-celestial-calc",
  "30-infernal-damage", "31-feywild-attack", "32-underdark-calc", "33-abyssal-percent",
}

local function A(id, arg) return app.activate(id, arg) end
local function stage(i)
  local st = app.st
  if i == 1 then A("tab", app.CALC) app.calc.scroll = 0
  elseif i == 2 then A("chart", 2)
  elseif i == 3 then
    -- A new row changes the page height, and the scroll is clamped to the
    -- height the previous frame measured, so the row goes in one frame and
    -- the scroll to the end the next.
    A("chart", 1) A("gadd", 0)
  elseif i == 4 then app.calc.scroll = 99999
  elseif i == 5 then
    A("gdel", 2) app.calc.scroll = 0
    A("mode", rules.ADVANTAGE)
    scripted(20, 11)
    A("roll", 0)                           -- Calculator: Roll attack
    settleAll()
  elseif i == 6 then
    scripted(7, 3)
    A("rolldmg", 0)                        -- Attack: Crit damage
    settleAll()
  elseif i == 7 then
    A("tab", app.ATTACK) A("mode", rules.NORMAL)
    scripted(12) A("roll", 0) settleAll()
  elseif i == 8 then
    A("mode", rules.DISADVANTAGE)
    scripted(1, 15) A("roll", 0) settleAll()
    app.views.attack.d20Anim.t = app.views.attack.d20Anim.revealAt + 0.12
  elseif i == 9 then
    A("mode", rules.NORMAL) A("sub", 2)
    st.checkMod, st.checkDc = 4, 14
    scripted(20) A("roll", 0) settleAll()
  elseif i == 10 then
    A("sub", 1) A("tab", app.DAMAGE)
    st.attack.groups = rules.parseDice("1d8+3d6+1d4", 5, 15)
    st.doubleDice = false
    scripted(8, 3, 6, 1, 4) A("roll", 0) settleAll()
  elseif i == 11 then
    A("tab", app.PERCENT) scripted(100) A("roll", 0) settleAll()
  elseif i == 12 then A("tab", app.DAMAGE) A("presets", 0)
  elseif i == 13 then
    A("psave", 0)
    app.sheet.nameFresh, app.sheet.nameBuf = false, "Espada longa +1"
  elseif i == 14 then A("pcancel", 0) app.sheet.confirmDelete = 2
  elseif i == 15 then
    sheet.close() A("tab", app.CALC)
    st.attack = rules.newAttack(9, "1d10+2d6", 5, 4, 1)
    st.active, st.targetHp, st.rollMode = 0, 60, rules.ADVANTAGE
  elseif i >= 16 and i <= 20 then
    st.attack = session.fresh().attack
    st.active, st.rollMode, st.targetHp = 1, rules.NORMAL, 20
    A("scheme", 0)
  elseif i == 21 then
    A("scheme", 0) A("tab", app.ATTACK) A("presets", 0) A("psave", 0)
    app.sheet.nameFresh, app.sheet.nameBuf = false, "Machado de guerra"
    A("pcommit", 0)
  elseif i == 22 then
    sheet.close()
    scripted(14) A("roll", 0)
    app.views.attack.d20Anim.t = 0.2       -- mid-tumble: Skip, Damage disabled
  elseif i == 23 then
    -- A phone with a notch and a gesture bar: the column must sit inside.
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    love.window.getSafeArea = function() return 0, math.floor(H * 0.04), W, H - math.floor(H * 0.04) - math.floor(H * 0.02) end
    A("tab", app.DAMAGE) settleAll()
  elseif i == 24 then A("presets", 0)
  elseif i == 25 then
    sheet.close() A("tab", app.CALC) app.calc.scroll = 0
    app.calc.scrub = 12
  elseif i == 26 then
    app.calc.scrub = -1
    st.palIdx, app.toast = 1, nil
    A("party", 0)
  elseif i == 27 then
    A("qnew", 0)
    app.sheet.nameFresh = false
    app.party.nameFresh, app.party.nameBuf = false, "Thessaly"
    A("qcolor", 4)
  elseif i == 28 then
    A("qcancel", 0)
    partysheet.offer(store.partyFile(store.fresh()), "dice-and-damage-party.json")
  elseif i == 29 then
    A("qcancel", 0) A("qpick", 2)
    A("tab", app.DAMAGE) scripted(6, 2, 5, 4) A("roll", 0) settleAll()
  elseif i >= 30 and i <= 34 then
    st = app.st
    local schemes = { 11, 7, 8, 9, 10 }
    st.palIdx = schemes[i - 29]
    local tabs = { app.CALC, app.DAMAGE, app.ATTACK, app.CALC, app.PERCENT }
    A("tab", tabs[i - 29])
    if i == 32 then A("roll", 0) settleAll() end
    if i == 34 then scripted(1) A("roll", 0) settleAll() end
  end
end

local frameNo, stepNo = 0, 0
function hooks.load() end
function hooks.update(dt) end
function hooks.note(id, arg) end
function hooks.frame()
  frameNo = frameNo + 1
  if frameNo < 3 then return end
  if stepNo >= 1 and names[stepNo]:sub(1, 1) ~= "-" then
    local name = names[stepNo]
    love.graphics.captureScreenshot(function(img)
      local f = assert(io.open(OUT .. name .. ".png", "wb"))
      f:write(img:encode("png"):getString())
      f:close()
    end)
  end
  stepNo = stepNo + 1
  if stepNo > #names then
    if frameNo > 0 then print("RENDERED") love.event.quit() end
    return
  end
  stage(stepNo)
end
return hooks
'''.replace("OUTDIR", out)

open(os.path.join(work, "hooks.lua"), "w").write(DRIVER)
conf = open(os.path.join(work, "conf.lua")).read()
conf = conf.replace("t.window.width     = 390", f"t.window.width     = {w}")
conf = conf.replace("t.window.height    = 844", f"t.window.height    = {h}")
conf = conf.replace('t.identity = "dnd-dice-and-damage"', 't.identity = "dnd-dice-and-damage-render"')
conf = conf.replace("t.window.resizable = true", "t.window.resizable = false")
open(os.path.join(work, "conf.lua"), "w").write(conf)

# A fresh save folder, so a session left by an earlier run cannot leak in.
save = os.path.expanduser("~/.local/share/love/dnd-dice-and-damage-render")
shutil.rmtree(save, ignore_errors=True)

env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1")
cmd = ["xvfb-run", "-a", "-s", f"-screen 0 {w + 40}x{h + 40}x24", "love", work]
r = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=env)
print((r.stdout + r.stderr)[-3000:])
print(len(os.listdir(out)), "images in", out)
