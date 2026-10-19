--[[
  tapmap_driver.lua -- replaces game/hooks.lua for test/tapmap.py.

  Taps every control on every screen, checks that each tap lands on the
  control under it AND reaches that control's action, then walks the app's
  cross-tab behaviour and the gestures through real input.

  MODE is set by tapmap.py:

    mouse   real OS mouse events: xdotool moves and clicks the X pointer, so
            each click travels through the X server, SDL and LOVE's event
            queue as a user's would.
    touch   touch events in window units, pushed into LOVE's event queue
            exactly as Event.cpp delivers a finger (normalizedToDPICoords
            gives window units). Each finger also gets the mouse events SDL
            synthesises for it, flagged istouch, which the app must ignore:
            every tap must run its action exactly once.

  Where to tap comes from the drawing model -- a control drawn at design
  point d under love.graphics.scale(S) appears at window point d * S -- and
  from the window position LOVE reports, never from the app's own input
  conversion, which is what is on trial.

  Three layers, because each one catches something the one before cannot:

    1. Every (id, arg) on a screen is unique.
    2. Every control, tapped, reaches its own action.
    3. The behaviour asked for, by real taps, reading back what each tab
       displays (the `shown` value each control registers).
--]]

local MODE = "MODE_HERE"

io.stdout:setvbuf("no")

function love.errorhandler(msg)
  print("TAPMAP ERROR " .. debug.traceback(tostring(msg), 2))
  os.exit(3)
end

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local session = require("session")
local tray = require("tray")
local sheet = require("sheet")
local store = require("store")
local partysheet = require("partysheet")

local hooks = {}

-- ---------------------------------------------------------------- plan

local plan, head = {}, 1
local waitFrames, waitUntil = 0, 0
local frameNo, checked = 0, 0
local failures = {}
local notes = {}

local function after(frames, fn) plan[#plan + 1] = { frames = frames, fn = fn } end
-- Waits in the app's own clock, which is what drives holds and animations:
-- on a slow software-rendered frame the app sees at most 0.1 s per update.
local function afterSeconds(s, fn) plan[#plan + 1] = { seconds = s, fn = fn } end

local function fail(msg) failures[#failures + 1] = msg end
local function expect(cond, msg)
  checked = checked + 1
  if not cond then fail(msg) end
end

function hooks.note(id, arg) notes[#notes + 1] = id .. "/" .. tostring(arg) end
local function lastNote() return notes[#notes] end

local function fixed(v) return function(lo, hi) return math.max(lo, math.min(hi, v)) end end

-- ---------------------------------------------------------------- input

local fingerId = 0
local finger = nil          -- the id of the finger currently down, touch mode

local function winPoint(dx, dy)
  return dx * ui.S, dy * ui.S
end

local function sh(cmd)
  local okay = os.execute(cmd)
  if okay ~= 0 and okay ~= true then fail("command failed: " .. cmd) end
end

local function moveTo(dx, dy)
  local wx, wy = winPoint(dx, dy)
  if MODE == "mouse" then
    local ox, oy = love.window.getPosition()
    sh(string.format("xdotool mousemove %d %d", math.floor(ox + wx + 0.5), math.floor(oy + wy + 0.5)))
  elseif finger then
    love.event.push("touchmoved", finger, wx, wy, 0, 0, 1)
    love.event.push("mousemoved", wx, wy, 0, 0, true)
  end
  app.lastPoint = { dx, dy }
end

local function down(dx, dy)
  if dx then app.lastPoint = { dx, dy } end
  local p = app.lastPoint
  local wx, wy = winPoint(p[1], p[2])
  if MODE == "mouse" then
    if dx then moveTo(dx, dy) end
    sh("xdotool mousedown 1")
  else
    fingerId = fingerId + 1
    finger = fingerId
    love.event.push("touchpressed", finger, wx, wy, 0, 0, 1)
    love.event.push("mousepressed", wx, wy, 1, true, 1)
  end
end

local function up()
  if MODE == "mouse" then
    sh("xdotool mouseup 1")
  else
    local p = app.lastPoint
    local wx, wy = winPoint(p[1], p[2])
    love.event.push("touchreleased", finger, wx, wy, 0, 0, 1)
    love.event.push("mousereleased", wx, wy, 1, true, 1)
    finger = nil
  end
end

-- ---------------------------------------------------------------- targets

local function find(id, arg)
  for _, h in ipairs(ui.hits) do
    if h.id == id and h.arg == arg then return h end
  end
end

local function shown(id, arg)
  local h = find(id, arg)
  return h and tostring(h.shown) or "(not on screen)"
end

--- A point inside t where t is the topmost target, or nil.
local function reachable(t)
  for gy = 1, 7 do
    for gx = 1, 7 do
      local fx = (gx % 2 == 0) and (8 - gx) or gx
      local fy = (gy % 2 == 0) and (8 - gy) or gy
      local px, py = t.x + t.w * fx / 8, t.y + t.h * fy / 8
      if ui.pick(px, py) == t then return px, py end
    end
  end
end

-- ---------------------------------------------------------------- screens

local A = function(id, arg) return app.activate(id, arg) end

local SCREEN_NAMES = {
  "calculator top", "calculator scrolled to the end", "calculator Damage vs AC",
  "attack roll after a roll", "ability check", "damage after a roll", "percent",
  "presets sheet from the calculator", "presets sheet naming, from attack",
  "presets sheet delete confirm, from damage",
  "the party", "the party, a new character", "the party, importing a party file",
  "the party, delete confirm",
}

local function settle(v)
  v:skip()
  v:advance(0)
end

local function setupScreen(i)
  sheet.close()
  partysheet.close()
  app.calc.scrub = -1
  ui.press = nil
  app.st = store.fresh()
  app.rng = fixed(12)
  tray.resetViews()
  app.calc.scroll = 0
  local st = app.st
  if i == 1 then app.showTab(app.CALC)
  elseif i == 2 then app.showTab(app.CALC) app.calc.scroll = 99999
  elseif i == 3 then app.showTab(app.CALC) st.chart = 2
  elseif i == 4 then app.showTab(app.ATTACK) st.attackSub = 1 A("roll", 0) settle(app.views.attack)
  elseif i == 5 then app.showTab(app.ATTACK) st.attackSub = 2
  elseif i == 6 then
    app.showTab(app.DAMAGE)
    st.attack.groups = rules.parseDice("2d6+1d8+1d4", 5, 15)
    A("roll", 0) settle(app.views.damage)
  elseif i == 7 then app.showTab(app.PERCENT)
  elseif i == 8 then app.showTab(app.CALC) st.attack.bonus = st.attack.bonus + 1 sheet.open()
  elseif i == 9 then app.showTab(app.ATTACK) sheet.open() sheet.action("psave", 0)
  elseif i == 10 then app.showTab(app.DAMAGE) sheet.open() app.sheet.confirmDelete = 2
  elseif i == 11 then app.showTab(app.CALC) partysheet.open()
  elseif i == 12 then app.showTab(app.ATTACK) partysheet.open() partysheet.action("qnew", 0)
  elseif i == 13 then app.showTab(app.DAMAGE) partysheet.offer(store.partyFile(store.fresh()), "")
  elseif i == 14 then app.showTab(app.CALC) partysheet.open() app.party.confirmDelete = 2
  end
end

local flows

local function sweep(i)
  local name = SCREEN_NAMES[i]
  local snap = {}
  for k, h in ipairs(ui.hits) do snap[k] = h end
  local seen = {}
  for _, t in ipairs(snap) do
    local key = t.id .. "/" .. tostring(t.arg)
    expect(not seen[key], name .. ": two controls share the id " .. key)
    seen[key] = true
  end

  local modalFrom = 0
  for k, t in ipairs(snap) do if t.id == "backdrop" or t.id == "qback" then modalFrom = k end end

  for k, t in ipairs(snap) do
    local key = t.id .. "/" .. tostring(t.arg)
    if k < modalFrom then
      expect(reachable(t) == nil, name .. ": " .. key .. " is reachable behind the sheet")
    else
      -- Each control is tapped on a freshly set-up screen, so what one tap
      -- does -- switch a tab, open a sheet -- cannot move the next target.
      local skip = false
      local noteCount
      after(3, function() setupScreen(i) end)
      after(3, function()
        local h = find(t.id, t.arg)
        local px, py
        if h then px, py = reachable(h) end
        if not px then
          fail(name .. ": " .. key .. " cannot be reached")
          skip = true
          return
        end
        noteCount = #notes
        down(px, py)
      end)
      after(3, function()
        if skip then return end
        checked = checked + 1
        local p = ui.press
        local landed = p and p.hit and p.hit.id == t.id and p.hit.arg == t.arg
        if not landed then
          local got = not p and "no press" or (not p.hit and "nothing" or (p.hit.id .. "/" .. tostring(p.hit.arg)))
          fail(name .. ": a tap on " .. key .. " pressed " .. got)
        end
        if t.id == "plot" then expect(app.calc.scrub >= 0, name .. ": pressing the plot did not scrub") end
        up()
      end)
      after(0, function()
        if skip then return end
        local new = #notes - noteCount
        if t.id == "plot" then
          expect(new == 0, name .. ": releasing the plot ran an action (" .. tostring(lastNote()) .. ")")
        else
          expect(new == 1 and lastNote() == key, name .. ": a tap on " .. key .. " ran " .. new
                 .. " actions (last " .. tostring(lastNote()) .. "), not exactly its own")
        end
      end)
    end
  end
end

local function screen(i)
  if i > #SCREEN_NAMES then flows() return end
  after(4, function() setupScreen(i) end)
  after(0, function() sweep(i) screen(i + 1) end)
end

-- ---------------------------------------------------------------- flows

--- A real tap on a control, scrolling the Calculator to find it if needed.
local function tap(id, arg)
  after(2, function() if app.st.tab == app.CALC and not find(id, arg) then app.calc.scroll = 0 end end)
  after(2, function() if app.st.tab == app.CALC and not find(id, arg) then app.calc.scroll = 99999 end end)
  after(3, function()
    local h = find(id, arg)
    local px, py
    if h then px, py = reachable(h) end
    if not px then fail("could not find " .. id .. "/" .. tostring(arg) .. " on tab " .. app.st.tab) return end
    down(px, py)
  end)
  after(4, function() if MODE == "mouse" or finger then up() end end)
end

--- Reads a displayed value on the current tab, scrolling to it if needed.
local function read(id, arg, into, k)
  after(2, function() if app.st.tab == app.CALC and not find(id, arg) then app.calc.scroll = 0 end end)
  after(2, function() if app.st.tab == app.CALC and not find(id, arg) then app.calc.scroll = 99999 end end)
  after(0, function() into[k] = shown(id, arg) end)
end

local function fresh(tab)
  after(3, function() setupScreen(1) app.showTab(tab) end)
end

local gestures, partyFlows

flows = function()
  local r = {}

  -- The Damage vs AC chip switches the chart, and Distribution switches back.
  fresh(app.CALC)
  tap("chart", 2)
  after(0, function() expect(app.st.chart == 2, "chart: Damage vs AC did not switch the chart") end)
  tap("chart", 1)
  after(0, function() expect(app.st.chart == 1, "chart: Distribution did not switch back") end)

  -- The tab icons switch tabs.
  for t = 1, 4 do
    tap("tab", t)
    after(0, function() expect(app.st.tab == t, "the tab icon " .. t .. " did not switch to its tab") end)
  end

  -- The small scheme button cycles the schemes, and wraps.
  fresh(app.CALC)
  for k = 1, 11 do tap("scheme", 0) end
  after(0, function() expect(app.st.palIdx == 1, "eleven taps on the scheme button left scheme " .. app.st.palIdx) end)
  tap("scheme", 0)
  after(0, function() expect(app.st.palIdx == 2 and shown("scheme", 0) == "Spellbook",
                             "the scheme button did not step to Spellbook (" .. shown("scheme", 0) .. ")") end)

  -- Edit on the Calculator; the Attack tab shows the same bonus, mode, AC.
  fresh(app.CALC)
  after(0, function() app.st.attackSub = 2 end)                -- left on ability checks
  tap("s.ac", 1) tap("s.ac", 1) tap("mode", 3) tap("s.bonus", 1)
  read("s.ac", 1, r, 1) read("s.bonus", 1, r, 2)
  after(0, function() expect(r[1] == "17" and r[2] == "+8", "calculator did not step: AC " .. r[1] .. ", bonus " .. r[2]) end)

  -- Roll attack on the Calculator switches to Attack and rolls it there.
  tap("roll", 0)
  after(3, function()
    expect(app.st.tab == app.ATTACK and app.st.attackSub == 1, "Roll attack did not land on the Attack roll tab")
    local d = app.views.attack.d20
    expect(d ~= nil, "Roll attack did not roll")
    if d then
      expect(d.mod == 8 and d.target == 17 and #d.dice == 2,
             "the roll used bonus " .. d.mod .. ", AC " .. d.target .. ", " .. #d.dice .. " dice")
    end
  end)
  read("s.ac", 1, r, 1) read("s.bonus", 1, r, 2) read("mode", 3, r, 3)
  after(0, function() expect(r[1] == "17" and r[2] == "+8" and r[3] == "on",
                             "Attack tab shows AC " .. r[1] .. ", bonus " .. r[2] .. ", advantage [" .. r[3] .. "]") end)

  -- ...and the other way: edits on the Attack tab show on the Calculator.
  tap("s.ac", -1) tap("mode", 1) tap("s.bonus", -1)
  tap("tab", app.CALC)
  read("s.ac", 1, r, 1) read("s.bonus", 1, r, 2) read("mode", 1, r, 3)
  after(0, function() expect(r[1] == "16" and r[2] == "+7" and r[3] == "on",
                             "Calculator after Attack edits shows AC " .. r[1] .. ", bonus " .. r[2]
                             .. ", disadvantage [" .. r[3] .. "]") end)

  -- Damage on the Attack tab switches to Damage and rolls, doubled on a crit.
  fresh(app.ATTACK)
  after(0, function() app.rng = fixed(20) end)                 -- every die on its top face
  tap("roll", 0)
  tap("tray", 0)                                               -- skip the tumble
  tap("rolldmg", 0)
  after(3, function()
    local d = app.views.damage.dmg
    expect(app.st.tab == app.DAMAGE, "Crit damage did not switch to the Damage tab")
    expect(d ~= nil and d.doubled and #d.dice == 2 * rules.diceCount(app.st.attack) and app.st.doubleDice,
           "after a crit the Damage tab rolled " .. (d and (#d.dice .. " dice, doubled " .. tostring(d.doubled)) or "nothing"))
    -- Counted from the preset itself, not from whatever the attack is now:
    -- the Longsword is 1d8 + 4, so a crit is two d8 and the + 4 once.
    local sides = {}
    for _, die in ipairs(d and d.dice or {}) do sides[#sides + 1] = die.sides end
    expect(d ~= nil and table.concat(sides, ",") == "8,8" and d.mod == 4,
           "a Longsword crit rolled d" .. table.concat(sides, ",d") .. " + " .. tostring(d and d.mod))
  end)
  read("s.g1", 1, r, 1) read("s.g2", 1, r, 2)
  after(0, function() expect(r[1] == "1d8" and r[2] == "(not on screen)",
                             "the hand-off edited the attack's dice: " .. r[1] .. ", " .. r[2]) end)
  tap("tab", app.ATTACK)
  after(0, function() app.rng = fixed(9) end)                  -- 9 + 7 = 16: a plain hit
  tap("roll", 0)
  tap("tray", 0)
  tap("rolldmg", 0)
  after(3, function()
    local d = app.views.damage.dmg
    expect(app.st.tab == app.DAMAGE and d ~= nil and not d.doubled and #d.dice == 1 and d.dice[1].sides == 8
           and not app.st.doubleDice,
           "after a plain hit the Damage tab rolled " .. (d and (#d.dice .. " dice, doubled " .. tostring(d.doubled)) or "nothing"))
  end)

  -- Damage dice are the same dice on the Calculator and the Damage tab.
  fresh(app.CALC)
  tap("gadd", 0) tap("gdie", 2) tap("s.g2", 1)                 -- 1d8 + 1d6 -> 1d8 + 1d8 -> 1d8 + 2d8
  read("s.g1", 1, r, 1) read("s.g2", 1, r, 2)
  tap("tab", app.DAMAGE)
  read("s.g1", 1, r, 3) read("s.g2", 1, r, 4)
  after(0, function() expect(r[1] == "1d8" and r[2] == "2d8" and r[3] == r[1] and r[4] == r[2],
                             "dice: calculator " .. r[1] .. " + " .. r[2] .. ", damage tab " .. r[3] .. " + " .. r[4]) end)
  tap("s.mod", 1) tap("gdel", 1)
  read("s.mod", 1, r, 5)
  tap("tab", app.CALC)
  read("s.g1", 1, r, 1) read("s.g2", 1, r, 2) read("s.mod", 1, r, 3)
  after(0, function() expect(r[1] == "2d8" and r[2] == "(not on screen)" and r[3] == r[5] and r[3] == "+5",
                             "after editing on the Damage tab the calculator shows " .. r[1] .. ", " .. r[2]
                             .. ", bonus " .. r[3]) end)

  -- Presets on the Calculator, the Attack tab and the Damage tab.
  for _, tab in ipairs({ app.CALC, app.ATTACK, app.DAMAGE }) do
    fresh(tab)
    tap("presets", 0)
    after(0, function() expect(app.sheet.open, "the presets bar did not open the sheet on tab " .. tab) end)
  end
  -- A preset loaded on the Damage tab changes the Calculator too.
  fresh(app.DAMAGE)
  tap("presets", 0)
  tap("pload", 2)                                              -- Brannoc's Greatsword: +8, 2d6 + 5
  read("s.g1", 1, r, 1) read("s.mod", 1, r, 2)
  tap("tab", app.CALC)
  read("s.g1", 1, r, 3) read("s.bonus", 1, r, 4) read("s.mod", 1, r, 5)
  after(0, function() expect(r[1] == "2d6" and r[2] == "+5" and r[3] == "2d6" and r[4] == "+8" and r[5] == "+5",
                             "preset from the Damage tab: damage tab " .. r[1] .. " " .. r[2]
                             .. ", calculator " .. r[3] .. " " .. r[4] .. " " .. r[5]) end)
  -- The ability check tab has no preset bar: a check is not an attack.
  fresh(app.ATTACK)
  after(3, function() app.st.attackSub = 2 end)
  after(0, function() expect(find("presets", 0) == nil, "the ability check tab shows the preset bar") end)

  -- Naming a preset: the keyboard comes up for the name and goes away after,
  -- typed text is kept by whole characters, backspace removes one.
  fresh(app.ATTACK)
  tap("presets", 0)
  tap("psave", 0)
  after(0, function()
    expect(sheet.isEditing() and love.keyboard.hasTextInput(), "Save as new did not start a name with text input on")
  end)
  if MODE == "mouse" then
    after(3, function() sh("xdotool type --delay 20 'Axe'") end)
    after(3, function() sh("xdotool key BackSpace") end)
    after(3, function() sh("xdotool type --delay 20 'es'") end)
  else
    after(3, function() love.event.push("textinput", "Axe") end)
    after(3, function() love.event.push("keypressed", "backspace", "backspace", false) end)
    after(3, function() love.event.push("textinput", "es") end)
  end
  after(3, function()
    expect(app.sheet.nameBuf == "Axes", "typing Axe, backspace, es gave " .. app.sheet.nameBuf)
  end)
  after(0, function() love.event.push("textinput", " ⚔ Ação ✓") end)   -- LOVE delivers UTF-8
  after(3, function()
    expect(app.sheet.nameBuf == "Axes ⚔ Ação ✓", "UTF-8 text arrived as " .. app.sheet.nameBuf)
  end)
  after(0, function() love.event.push("keypressed", "backspace", "backspace", false) end)
  after(3, function()
    expect(app.sheet.nameBuf == "Axes ⚔ Ação ", "backspace after ✓ left " .. app.sheet.nameBuf)
  end)
  tap("pcommit", 0)
  after(0, function()
    local p = app.st.presets[#app.st.presets]
    expect(p and p.name == "Axes ⚔ Ação" and app.st.active == #app.st.presets,
           "the committed preset is " .. tostring(p and p.name))
    expect(not sheet.isEditing() and not love.keyboard.hasTextInput(), "text input stayed on after Save")
  end)
  -- Keys typed outside a name do not type; digits switch tabs instead.
  after(0, function() app.sheet.open = false end)
  after(0, function() love.event.push("textinput", "zz") end)
  after(3, function() expect(app.sheet.nameBuf == "Axes ⚔ Ação ", "text typed outside a name changed it") end)

  partyFlows()
end

-- ---------------------------------------------------------------- the party

partyFlows = function()
  local r = {}

  -- A new attack from the Damage tab: back to the Attack tab and a new d20,
  -- with the Calculator's bonus and AC.
  fresh(app.DAMAGE)
  after(0, function() app.rng = fixed(12) end)
  tap("roll", 0)
  tap("tray", 0)
  tap("rollatk", 0)
  after(3, function()
    local d = app.views.attack.d20
    expect(app.st.tab == app.ATTACK and app.st.attackSub == 1, "New attack on the Damage tab did not land on Attack roll")
    expect(d ~= nil and d.mod == 7 and d.target == 15 and d.natural == 12,
           "New attack rolled " .. (d and (d.natural .. " + " .. d.mod .. " vs " .. d.target) or "nothing"))
  end)

  -- Switching characters brings back each one's own attack and presets.
  fresh(app.CALC)
  tap("party", 0)
  after(0, function() expect(app.party.open, "the character's name did not open the party") end)
  tap("qpick", 2)
  after(0, function()
    expect(not app.party.open and app.st.current == 2, "picking Vex did not switch and close")
    expect(rules.encodeDice(app.st.attack.groups) == "1d8+3d6" and app.st.presets[1].name == "Rapier and Sneak Attack",
           "Vex's attack and presets did not come back")
  end)
  tap("s.bonus", 1)                                            -- Vex now +8
  tap("party", 0) tap("qpick", 1)
  read("s.bonus", 1, r, 1)
  tap("party", 0) tap("qpick", 2)
  read("s.bonus", 1, r, 2)
  after(0, function() expect(r[1] == "+7" and r[2] == "+8", "working attacks are shared between characters: "
                             .. r[1] .. ", " .. r[2]) end)
  read("party", 0, r, 3)
  after(0, function() expect(r[3] == "Vex", "the top bar shows " .. r[3]) end)

  -- A new character: named, coloured, starting from the attack on the table.
  tap("party", 0)
  tap("qnew", 0)
  after(0, function() expect(love.keyboard.hasTextInput(), "naming a character did not bring up text input") end)
  after(3, function() love.event.push("textinput", "Thessaly") end)
  tap("qcolor", 4)
  tap("qsave", 0)
  after(0, function()
    local c = app.st.party[4]
    expect(#app.st.party == 4 and app.st.current == 4 and c and c.name == "Thessaly" and c.color == 4
           and #c.presets == 0 and c.attack.bonus == 8 and not love.keyboard.hasTextInput(),
           "the new character is " .. tostring(c and (c.name .. " colour " .. c.color .. ", " .. #c.presets .. " presets")))
  end)
  -- Deleting asks first. (Save leaves the sheet open on the list.)
  tap("qdel", 4)
  after(0, function() expect(#app.st.party == 4, "one tap deleted a character") end)
  tap("qdel", 4)
  after(0, function() expect(#app.st.party == 3 and app.st.current == 3, "the second tap did not delete it") end)

  -- Export and import through the clipboard, in the web app's formats.
  fresh(app.CALC)
  after(0, function() love.system.setClipboardText("") end)
  tap("party", 0)
  tap("qexport", 0)
  after(2, function()
    local clip = love.system.getClipboardText()
    expect(clip == store.characterFile(app.st.party[1]), "Export did not copy Brannoc's character file")
    expect(love.filesystem.read("exports/brannoc.json") == clip, "Export did not write exports/brannoc.json")
    app.st.party[1].note = "Changed here"
  end)
  tap("qpaste", 0)
  after(0, function() expect(app.party.mode == "import" and app.party.import.kind == "character",
                             "Paste did not offer the character") end)
  tap("qreplace", 0)
  after(0, function() expect(#app.st.party == 3 and app.st.party[1].note == "Fighter 5 · Champion",
                             "Replace did not put the file's Brannoc back") end)
  tap("qexportall", 0)
  after(2, function()
    expect(love.system.getClipboardText() == store.partyFile(app.st), "Export party did not copy the party file")
    app.st.party[2].name = "Somebody else"
  end)
  tap("qpaste", 0)
  tap("qadd", 0)
  after(0, function()
    local names = {}
    for _, c in ipairs(app.st.party) do names[#names + 1] = c.name end
    expect(table.concat(names, ",") == "Brannoc,Somebody else,Sister Ilse,Brannoc (2),Vex,Sister Ilse (2)",
           "Add gave " .. table.concat(names, ","))
  end)
  tap("qpaste", 0)
  tap("qparty", 0)
  after(0, function() expect(#app.st.party == 3 and app.st.party[2].name == "Vex" and app.st.current == 1,
                             "Replace the party did not") end)
  -- A file that is not a party is refused, and nothing changes.
  after(0, function() love.system.setClipboardText("{\"format\":\"nope\"}") end)
  tap("qpaste", 0)
  after(0, function() expect(app.party.import and app.party.import.error ~= nil and #app.st.party == 3,
                             "a foreign file was not refused") end)
  tap("qcancel", 0)

  gestures()
end

-- ---------------------------------------------------------------- gestures

gestures = function()
  local acBefore, scrollBefore, scrubSeen, from

  after(4, function() setupScreen(1) app.st.ac = 15 end)
  after(3, function() app.calc.scroll = 99999 end)
  after(3, function()
    local h = find("s.ac", 1)
    app.calc.scroll = math.max(0, app.calc.scroll + h.y - app.calc.viewT - 200)
  end)

  -- Tap: one step.
  after(3, function() acBefore = app.st.ac local h = find("s.ac", 1) down(h.x + h.w / 2, h.y + h.h / 2) end)
  after(2, function() up() end)
  after(4, function() expect(app.st.ac == acBefore + 1, "a tap on + stepped " .. (app.st.ac - acBefore) .. " times, not once") end)

  -- Hold: repeats after the delay.
  afterSeconds(1.2, function() acBefore = app.st.ac local h = find("s.ac", 1) down(h.x + h.w / 2, h.y + h.h / 2) end)
  after(2, function() up() end)
  after(4, function() expect(app.st.ac >= acBefore + 4, "holding + for 1.2 s stepped only " .. (app.st.ac - acBefore)) end)

  -- Drag that starts on a control: scrolls, never presses.
  after(3, function() app.calc.scroll = 99999 end)
  after(3, function()
    acBefore, scrollBefore = app.st.ac, app.calc.scroll
    local h = find("s.ac", 1)
    from = { h.x + h.w / 2, h.y + h.h / 2 }
    down(from[1], from[2])
  end)
  for k = 1, 8 do after(1, function() moveTo(from[1], from[2] + k * 12) end) end
  after(2, function() up() end)
  after(4, function()
    expect(app.st.ac == acBefore, "a drag that started on + stepped the value")
    expect(app.calc.scroll < scrollBefore - 20, "a drag that started on a control did not scroll ("
           .. scrollBefore .. " -> " .. app.calc.scroll .. ")")
  end)

  -- Plot scrub: a drag across the plot reads values, release clears them.
  after(3, function() app.calc.scroll = 0 end)
  after(3, function() local h = find("plot", 0) down(h.x + 20, h.y + h.h / 2) end)
  after(1, function() local h = find("plot", 0) moveTo(h.x + h.w * 0.6, h.y + h.h / 2) end)
  after(3, function() scrubSeen = app.calc.scrub up() end)
  after(4, function()
    expect(scrubSeen > 0, "dragging across the plot did not scrub (" .. tostring(scrubSeen) .. ")")
    expect(app.calc.scrub == -1, "releasing did not clear the scrub")
    expect(app.st.chart == 1, "scrubbing the plot changed the chart")
  end)

  -- Leaving a control before release cancels it.
  after(3, function() acBefore = app.st.ac local h = find("s.ac", 1) down(h.x + h.w / 2, h.y + h.h / 2) end)
  after(1, function() local h = find("s.ac", 1) moveTo(h.x + h.w + 40, h.y + h.h / 2) end)
  after(2, function() up() end)
  after(4, function() expect(app.st.ac == acBefore, "a press dragged off + still stepped on release") end)

  if MODE == "touch" then
    -- The newest finger owns the press: a release from an older one does not
    -- act, and the new finger's own release does.
    after(3, function()
      local h = find("s.ac", 1)
      acBefore = app.st.ac
      local wx, wy = winPoint(h.x + h.w / 2, h.y + h.h / 2)
      love.event.push("touchpressed", 901, wx, wy, 0, 0, 1)      -- finger A
      love.event.push("touchpressed", 902, wx, wy, 0, 0, 1)      -- finger B takes over
      love.event.push("touchreleased", 901, wx, wy, 0, 0, 1)     -- A lifts: ignored
    end)
    after(2, function()
      expect(ui.press ~= nil and ui.press.touch == 902, "an older finger's release ended the newer finger's press")
      local h = find("s.ac", 1)
      local wx, wy = winPoint(h.x + h.w / 2, h.y + h.h / 2)
      love.event.push("touchreleased", 902, wx, wy, 0, 0, 1)
    end)
    after(3, function() expect(app.st.ac == acBefore + 1, "two overlapping fingers stepped " .. (app.st.ac - acBefore)) end)
    -- The watchdog: with it on, a press whose finger SDL no longer has is
    -- dropped after a moment, so a lost release cannot leave + held.
    after(0, function() app.touchWatchdog = true end)
    afterSeconds(1.5, function()
      acBefore = app.st.ac
      local h = find("s.ac", 1)
      local wx, wy = winPoint(h.x + h.w / 2, h.y + h.h / 2)
      love.event.push("touchpressed", 903, wx, wy, 0, 0, 1)      -- never released
    end)
    after(0, function()
      expect(ui.press == nil, "a press whose release was lost was never dropped")
      expect(app.st.ac == acBefore, "a press whose release was lost stepped " .. (app.st.ac - acBefore) .. " times")
    end)
  end

  after(0, function()
    print(string.format("TAPMAP mode %s window %dx%d scale %.3f at %d,%d", MODE,
          love.graphics.getWidth(), love.graphics.getHeight(), ui.S, love.window.getPosition()))
    print("TAPMAP " .. checked .. " checks, " .. #failures .. " failures")
    for _, f in ipairs(failures) do print("  FAIL " .. f) end
    love.event.quit()
  end)
end

-- ---------------------------------------------------------------- loop

-- Pushed fingers are not ones SDL can see, so the lost-touch watchdog would
-- drop every one of them; it is off except for the test that checks it.
function hooks.load() app.touchWatchdog = false end
function hooks.update(dt) end

function hooks.frame()
  frameNo = frameNo + 1
  if frameNo == 5 then screen(1) end
  if frameNo < 5 then return end
  if waitFrames > 0 then waitFrames = waitFrames - 1 return end
  if app.clock < waitUntil then return end
  local s = plan[head]
  if not s then return end
  head = head + 1
  local okay, err = pcall(s.fn)
  -- A failing step becomes a failure and the plan carries on.
  if not okay then fail("driver step threw " .. tostring(err)) end
  if s.seconds then
    waitFrames, waitUntil = 0, app.clock + s.seconds
  else
    waitFrames = s.frames
  end
end

return hooks
