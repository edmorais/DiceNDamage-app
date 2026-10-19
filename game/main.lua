--[[
  Dice & Damage -- the Damage Calculator and the Dice Roller as one app.

  A LOVE port of the Processing prototype. Portrait, one 390-unit column,
  every control sized for a thumb and acting on release.

  Every tab works on one attack. Its to-hit bonus, damage dice, damage bonus,
  attacks per round and crit range are the same values wherever they appear,
  and so are the situation -- enemy AC, roll mode, the damage you are trying
  to deal. Change the AC on the Calculator and the Attack tab rolls against
  it; add a d6 on the Damage tab and the Calculator's odds include it.

  The tabs also form a sequence, one roll handing on to the next:

    Calculator   Roll attack   switches to Attack and rolls the d20
    Attack       Damage        switches to Damage and rolls the dice,
                               doubled when the d20 was a crit

  Ability checks and the d100 sit outside that sequence. A check has its own
  modifier and DC, so a Dex check never edits the attack.

  Presets store the attack and are opened from the bar at the top of the
  Calculator, the Attack tab and the Damage tab. The situation is deliberately
  not part of a preset: the same longsword meets a different AC every fight.

  Touch / mouse                          Keys (desktop)
    tap                                   1-4          switch tabs
    drag the chart     read exact odds    space/enter  roll
    drag elsewhere     scroll             p            presets
    wheel              scroll             n / a / v    normal, adv, disadv
    hold - or +        repeat             c            next colour scheme
    back button        close the sheet,   escape       close the sheet, quit
                       then quit

  The party -- characters, each with its own presets and working attack --
  is written to party.json in the save folder a moment after it stops
  changing, when the app loses focus, and on quit. party.json is the web
  app's party file with the table's settings added, so it loads there too.
  A session.txt from the first app or the prototype becomes a character on
  the first launch of this one, and is kept.

  Modules
    rules, damage, rolls, session, palettes   plain Lua, tested by test/logic.lua
    ui, icons                                 drawing, widgets, touch targets
    tray, calc, attack, damagetab, sheet      the screens
    app                                       the state they share
    hooks                                     the seam the test drivers replace
--]]

local app = require("app")
local ui = require("ui")
local icons = require("icons")
local rules = require("rules")
local rolls = require("rolls")
local session = require("session")
local store = require("store")
local partysheet = require("partysheet")
local palettes = require("palettes")
local tray = require("tray")
local calc = require("calc")
local attack = require("attack")
local damagetab = require("damagetab")
local sheet = require("sheet")
local hooks = require("hooks")

local lg = love.graphics

local PARTY = "party.json"
local UNREADABLE = "party.unreadable.json"
local OLD_SESSION = "session.txt"
local SLOP = 10              -- design units of forgiveness around a held control
local LOST_TOUCH = 0.25      -- seconds a press may outlive every finger

app.touchWatchdog = true

-- ---------------------------------------------------------------- session

local function loadSession()
  app.st = store.fresh()
  if love.filesystem.getInfo(PARTY) then
    local text = love.filesystem.read(PARTY)
    local st = type(text) == "string" and store.decodeState(text)
    if st then
      app.st = st
      app.savedText = store.encodeState(st)
    else
      -- Not a party this build can read. Keep it rather than overwrite it on
      -- the first autosave, and start from the examples.
      if type(text) == "string" then love.filesystem.write(UNREADABLE, text) end
      love.filesystem.remove(PARTY)
      app.say("Party file unreadable; kept as " .. UNREADABLE)
    end
    return
  end
  -- The first launch after the first app: its presets become a character.
  -- session.txt is left where it is.
  if love.filesystem.getInfo(OLD_SESSION) then
    local st = store.migrate(love.filesystem.read(OLD_SESSION) or "")
    if st then
      app.st = st
      app.say("Your presets are now a character, My character")
    end
  end
end

local function saveSession()
  if not app.st then return end
  local text = store.encodeState(app.st)
  if text == app.savedText then return end
  local okay = love.filesystem.write(PARTY, text)
  if okay then app.savedText = text end
end
app.saveSession = saveSession

-- ---------------------------------------------------------------- actions

local function showTab(t)
  app.st.tab = t
  app.calc.scrub = -1
  ui.press = nil
end

local function rollAttack()
  local st = app.st
  app.views.attack:setD20(rolls.attack(app.rng, st.attack.bonus, st.rollMode, rules.critMin(st.attack), st.ac),
                          attack.d20Expr(true))
end

--- Calculator or Damage -> Attack: switch, and throw a new d20 with what the
--- Calculator shows, in attack mode even if the tab was last left on ability
--- checks.
local function rollAttackFromCalculator()
  showTab(app.ATTACK)
  app.st.attackSub = 1
  rollAttack()
end

--- Attack -> Damage: switch, and roll the attack's damage dice. The crit
--- toggle is set from the d20 so the Damage tab shows what it rolled; after
--- a crit, further rolls there stay doubled until it is turned off.
local function rollDamageFromAttack()
  local st = app.st
  local r = app.views.attack.d20
  st.doubleDice = r ~= nil and r.crit
  showTab(app.DAMAGE)
  app.views.damage:setDamage(rolls.damage(app.rng, st.attack.groups, st.attack.mod, st.doubleDice))
end

local function rollCurrent()
  local st = app.st
  if st.tab == app.CALC then
    rollAttackFromCalculator()
    return
  end
  local v = tray.currentView()
  if v:rolling() then
    v:skip()
    return
  end
  if st.tab == app.ATTACK and st.attackSub == 1 then
    rollAttack()
  elseif st.tab == app.ATTACK then
    v:setD20(rolls.check(app.rng, st.checkMod, st.rollMode, st.checkDc), attack.d20Expr(false))
  elseif st.tab == app.DAMAGE then
    v:setDamage(rolls.damage(app.rng, st.attack.groups, st.attack.mod, st.doubleDice))
  else
    v:setDamage(rolls.percent(app.rng))
  end
end

local function step(id, dir, mag)
  hooks.note(id, dir)
  local st = app.st
  local a = st.attack
  local d = dir * mag
  if id == "s.ac" then
    st.ac = rules.clamp(st.ac + d, rules.AC_MIN, rules.AC_MAX)
  elseif id == "s.bonus" then
    a.bonus = rules.clamp(a.bonus + d, rules.BONUS_MIN, rules.BONUS_MAX)
  elseif id == "s.attacks" then
    a.attacks = rules.clamp(a.attacks + d, rules.ATTACKS_MIN, rules.ATTACKS_MAX)
  elseif id == "s.mod" then
    a.mod = rules.clamp(a.mod + d, rules.MOD_MIN, rules.MOD_MAX)
  elseif id == "s.checkmod" then
    st.checkMod = rules.clamp(st.checkMod + d, rules.CHECK_MOD_MIN, rules.CHECK_MOD_MAX)
  elseif id == "s.checkdc" then
    st.checkDc = rules.clamp(st.checkDc + d, 0, rules.DC_MAX)
  elseif id:sub(1, 3) == "s.g" then
    local g = a.groups[tonumber(id:sub(4))]
    if g then
      -- The cap counts every die in the attack, so growing one group is
      -- limited by what the others already take.
      local ceiling = math.min(rules.MAX_DICE, g.n + rules.room(a))
      g.n = rules.clamp(g.n + d, 1, math.max(1, ceiling))
    end
  end
end

local function activate(id, arg)
  hooks.note(id, arg)
  if id ~= "pdel" then app.sheet.confirmDelete = 0 end
  if id:sub(1, 1) == "q" then
    partysheet.action(id, arg)
    return
  end
  local st = app.st
  local a = st.attack

  if id == "tab" then
    showTab(arg)
  elseif id == "scheme" then
    st.palIdx = st.palIdx % #palettes + 1
  elseif id == "schemeback" then
    st.palIdx = (st.palIdx - 2) % #palettes + 1
  elseif id == "chart" then
    st.chart = arg
  elseif id == "ccdf" then
    st.showCcdf = not st.showCcdf
  elseif id == "mode" then
    st.rollMode = arg
  elseif id == "crit" then
    a.crit = arg
  elseif id == "sub" then
    st.attackSub = arg
  elseif id == "gdie" then
    if a.groups[arg] then a.groups[arg].d = rules.nextSize(a.groups[arg].d) end
  elseif id == "gdel" then
    if #a.groups > 1 and a.groups[arg] then table.remove(a.groups, arg) end
  elseif id == "gadd" then
    if #a.groups < rules.MAX_GROUPS and rules.room(a) >= 1 then a.groups[#a.groups + 1] = { n = 1, d = 6 } end
  elseif id == "double" then
    st.doubleDice = not st.doubleDice
  elseif id == "roll" then
    rollCurrent()
  elseif id == "rolldmg" then
    rollDamageFromAttack()
  elseif id == "rollatk" then
    rollAttackFromCalculator()
  elseif id == "party" then
    partysheet.open()
  elseif id == "tray" then
    if st.tab ~= app.CALC then tray.currentView():skip() end
  elseif id == "presets" then
    sheet.open()
  else
    sheet.action(id, arg)
  end
end

--- The tabs that carry the preset bar.
local function presetBarShown()
  local st = app.st
  return st.tab == app.CALC or st.tab == app.DAMAGE or (st.tab == app.ATTACK and st.attackSub == 1)
end

-- ---------------------------------------------------------------- update

function love.update(dt)
  dt = math.min(0.1, dt)
  app.clock = app.clock + dt
  hooks.update(dt)
  for _, v in ipairs(tray.allViews()) do v:advance(dt) end
  if app.toastTime > 0 then app.toastTime = app.toastTime - dt end

  local press = ui.press

  -- A press that outlives every finger for a moment lost its release -- the
  -- notification shade came down, or the system took the gesture -- so it is
  -- dropped, and a held stepper cannot count on by itself. The grace period
  -- covers a release that is still in the queue behind this frame.
  if press and press.touch and app.touchWatchdog and love.touch then
    if #love.touch.getTouches() == 0 then
      press.lost = (press.lost or 0) + dt
      if press.lost > LOST_TOUCH then ui.press, press = nil, nil end
    else
      press.lost = 0
    end
  end

  -- A held stepper waits, then repeats, then repeats in fives once the hold
  -- is long enough that the user is clearly crossing a range.
  if press and press.hit and ui.isStepper(press.hit) and not press.scrolling then
    press.t = press.t + dt
    if press.t >= 0.42 then
      if not press.repeated then
        press.repeated = true
        press.acc = 0
        step(press.hit.id, press.hit.arg, 1)
      end
      press.acc = press.acc + dt
      local mag = 1
      while press.acc >= 0.075 do
        press.acc = press.acc - 0.075
        step(press.hit.id, press.hit.arg, mag)
      end
    end
  end

  -- Write the party a moment after the last change. Encoding a whole party
  -- every frame would be waste on a phone, so whether anything changed is
  -- looked at four times a second.
  app.sinceCheck = (app.sinceCheck or 1) + dt
  if app.sinceCheck >= 0.25 then
    app.sinceCheck = 0
    app.dirty = store.encodeState(app.st) ~= app.savedText
  end
  if app.dirty then
    app.saveIn = app.saveIn - dt
    if app.saveIn <= 0 then
      saveSession()
      app.dirty, app.saveIn = false, 0.6
    end
  else
    app.saveIn = 0.6
  end
end

-- ---------------------------------------------------------------- draw

--- The scheme button: three swatches of the scheme it is showing, no name.
--- The target is larger than the pill so it is easy to hit with a thumb.
local function drawSchemeButton(p, right, y, h)
  local sw, gap, pad, ph = 8, 3, 10, 30
  local pw = 3 * sw + 2 * gap + pad * 2
  local px, py = right - pw, y + (h - ph) * 0.5
  ui.box(ui.isDown("scheme", 0) and p.barLow or p.sunken, px, py, pw, ph, 10)
  ui.outline(p.edge, px, py, pw, ph, 10, 1, 1)
  local sw3 = { p.accent, p.crit, p.barHigh }
  for i = 1, 3 do ui.box(sw3[i], px + pad + (i - 1) * (sw + gap), py + 8, sw, ph - 16, 2) end
  local t = ui.target("scheme", 0, px - 7, y, pw + 14, h)
  if t then t.shown = p.name end
end

--- Who is playing: the character's badge, name and note. A tap opens the
--- party.
local function drawTopBar(p, x, y, w, h)
  local c = store.char(app.st)
  local down = ui.isDown("party", 0)
  local bw = w - 64 - 8
  if down then ui.box(p.sunken, x - 6, y, bw + 6, h, 23) end
  partysheet.emblem(p, c, x + 18, y + h * 0.5, 18)
  local tx = x + 46
  local maxW = bw - 46 - 18
  if c.note ~= "" then
    ui.txt(ui.fit(c.name, 22, maxW, "display"), tx, y + 1, 22, p.ink, 1, "left", "display")
    ui.txt(ui.fit(c.note, ui.LABEL + 1, maxW), tx, y + 26, ui.LABEL + 1, p.inkDim)
  else
    ui.txtIn(ui.fit(c.name, 22, maxW, "display"), tx, y, h, 22, p.ink, 1, "left", "display")
  end
  -- A small chevron says the name opens something.
  local vx, vy = x + bw - 12, y + h * 0.5
  ui.set(p.inkDim, 1)
  love.graphics.setLineWidth(1.6)
  love.graphics.line(vx - 4, vy - 2, vx, vy + 2, vx + 4, vy - 2)
  love.graphics.setLineWidth(1)
  local t = ui.target("party", 0, x - 6, y, bw + 6, h)
  if t then t.shown = c.name end
  drawSchemeButton(p, x + w, y, h)
end

local function drawToast(p)
  if not app.toast or app.toastTime <= 0 then return end
  local a = math.min(1, app.toastTime / 0.3)
  local w, h = math.min(ui.tw(app.toast, ui.BODY) + 32, ui.COL_W), 38
  -- Above the Roll button normally; near the top while the preset sheet is
  -- up, since the sheet rises from the bottom and the toast is about it.
  local x = ui.COLX - ui.PAD + (ui.DESIGN_W - w) * 0.5
  local y = (app.sheet.open or app.party.open) and ui.TOP + 72 or ui.VH - 14 - 58 - 12 - h
  ui.box(p.ink, x, y, w, h, 12, a * 0.94)
  ui.txtIn(ui.fit(app.toast, ui.BODY, w - 16), x + w * 0.5, y, h, ui.BODY, p.bg, a, "center")
end

function love.draw()
  ui.computeLayout()
  local p = app.pal()
  lg.clear(p.bg[1], p.bg[2], p.bg[3], 1)
  ui.beginFrame()

  lg.push()
  lg.scale(ui.S)

  local x, w = ui.COLX, ui.COL_W
  local y = ui.TOP + 14
  drawTopBar(p, x, y, w, 46)
  y = y + 46 + 8
  ui.chips(p, "tab", x, y, w, 42, icons.NAMES, app.st.tab, nil, 22)
  y = y + 42 + 10

  local tab = app.st.tab
  if tab == app.CALC then calc.draw(p, y)
  elseif tab == app.ATTACK then attack.draw(p, y)
  elseif tab == app.DAMAGE then damagetab.draw(p, y)
  else damagetab.drawPercent(p, y) end

  if app.sheet.open then sheet.draw(p) end
  if app.party.open then partysheet.draw(p) end
  drawToast(p)
  lg.pop()

  hooks.frame()
end

-- ---------------------------------------------------------------- input
-- Touches and mouse positions both arrive in window units; ui.toDesign is
-- the one conversion. See the note at the top of ui.lua.

local function onPress(dx, dy, touchId)
  local t = ui.pick(dx, dy)
  local c = app.calc
  local press = {
    hit = t, x = dx, y = dy, touch = touchId, t = 0, acc = 0,
    repeated = false, scrolling = false, scrubbing = false,
    canScroll = app.st.tab == app.CALC and not app.sheet.open and not app.party.open
      and dy >= c.viewT and dy <= c.viewB,
    scroll0 = c.scroll,
  }
  ui.press = press
  -- The plot is the one target that acts on press: dragging across it reads
  -- values. It has an id of its own -- when it shared "chart" with the chart
  -- chips, pressing "Damage vs AC" started a scrub instead of switching.
  if t and t.id == "plot" then
    press.scrubbing = true
    calc.scrubAt(dx)
  end
end

local function onMove(dx, dy)
  local press = ui.press
  if not press then return end
  local c = app.calc
  if press.scrubbing then
    calc.scrubAt(dx)
    return
  end
  if press.scrolling then
    c.scroll = press.scroll0 - (dy - press.y)
    return
  end
  -- A vertical drag in the scroll view is a scroll, whatever it started on,
  -- unless a stepper has already started repeating under the finger.
  if press.canScroll and not press.repeated and math.abs(dy - press.y) > 8 then
    press.scrolling = true
    press.hit = nil
    c.scroll = press.scroll0 - (dy - press.y)
    return
  end
  -- Anywhere else, leaving the control plus a margin cancels it. A fixed
  -- travel distance would either cancel a finger that is holding still or
  -- fail to cancel a real drag off a small button.
  if press.hit and not ui.inside(press.hit, dx, dy, SLOP) then press.hit = nil end
end

local function onRelease(dx, dy)
  local press = ui.press
  if not press then return end
  if press.scrubbing then
    app.calc.scrub = -1
    ui.press = nil
    return
  end
  local t = press.hit
  ui.press = nil
  if not t or press.scrolling or not ui.inside(t, dx, dy, SLOP) then return end
  if ui.isStepper(t) then
    if not press.repeated then step(t.id, t.arg, 1) end
  else
    activate(t.id, t.arg)
  end
end

-- The newest finger owns the press; a move or a release from any other one
-- is ignored. Nothing blocks a new press, deliberately: a guard that waits
-- for a release it might never see would leave the whole interface dead.
function love.touchpressed(id, x, y)
  local dx, dy = ui.toDesign(x, y)
  onPress(dx, dy, id)
end

function love.touchmoved(id, x, y)
  local press = ui.press
  if not press or press.touch ~= id then return end
  onMove(ui.toDesign(x, y))
end

function love.touchreleased(id, x, y)
  local press = ui.press
  if not press or press.touch ~= id then return end
  onRelease(ui.toDesign(x, y))
end

-- SDL also reports every touch as a mouse event with istouch set; those are
-- dropped, so a tap is handled once, by the touch handlers.
function love.mousepressed(x, y, button, istouch)
  if istouch or button ~= 1 then return end
  local dx, dy = ui.toDesign(x, y)
  onPress(dx, dy, nil)
end

function love.mousemoved(x, y, _, _, istouch)
  local press = ui.press
  if istouch or not press or press.touch then return end
  onMove(ui.toDesign(x, y))
end

function love.mousereleased(x, y, button, istouch)
  local press = ui.press
  if istouch or button ~= 1 or not press or press.touch then return end
  onRelease(ui.toDesign(x, y))
end

function love.wheelmoved(_, y)
  if app.st.tab == app.CALC and not app.sheet.open and not app.party.open then
    app.calc.scroll = app.calc.scroll - y * 48
  end
end

-- ---------------------------------------------------------------- keys

function love.keypressed(key, _, isrepeat)
  if sheet.isEditing() then
    if key == "escape" then activate("pcancel", 0)
    elseif key == "return" or key == "kpenter" then activate("pcommit", 0)
    elseif key == "backspace" then sheet.backspace() end
    return
  end
  if partysheet.isEditing() then
    if key == "escape" then activate("qcancel", 0)
    elseif key == "return" or key == "kpenter" then activate("qsave", 0)
    elseif key == "backspace" then partysheet.backspace() end
    return
  end
  -- Escape is also the Android back button: it closes a sheet, and
  -- otherwise leaves the app.
  if key == "escape" then
    if app.party.open and app.party.mode ~= "list" then activate("qcancel", 0)
    elseif app.party.open then partysheet.close()
    elseif app.sheet.open then sheet.close()
    else saveSession() love.event.quit() end
    return
  end
  if app.party.open then
    if key == "k" then partysheet.close() end
    if (key == "v" or key == "insert") and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") or key == "insert")
       and app.party.mode == "list" then partysheet.paste() end
    return
  end
  if app.sheet.open then
    if key == "p" then sheet.close() end
    return
  end
  if isrepeat then return end
  local st = app.st
  if key == "1" or key == "2" or key == "3" or key == "4" then showTab(tonumber(key))
  elseif key == "space" or key == "return" or key == "kpenter" then activate("roll", 0)
  elseif key == "c" then
    activate(love.keyboard.isDown("lshift", "rshift") and "schemeback" or "scheme", 0)
  elseif key == "r" then activate("rollatk", 0)
  elseif key == "k" then partysheet.open()
  elseif key == "[" or key == "]" then
    local n = #st.party
    store.switch(st, (st.current - 1 + (key == "]" and 1 or -1)) % n + 1)
    app.calc.scrub = -1
    app.say("Playing " .. store.char(st).name)
  elseif key == "p" and presetBarShown() then sheet.open()
  elseif key == "n" then st.rollMode = rules.NORMAL
  elseif key == "a" then st.rollMode = rules.ADVANTAGE
  elseif key == "v" then st.rollMode = rules.DISADVANTAGE
  end
end

function love.textinput(t)
  if sheet.isEditing() then sheet.type(t)
  elseif partysheet.isEditing() then partysheet.type(t) end
end

-- A character file, a party file or a session.txt dropped on the window.
function love.filedropped(file)
  local okay = pcall(file.open, file, "r")
  if not okay then return end
  local text = file:read()
  file:close()
  sheet.close()
  partysheet.offer(type(text) == "string" and text or "", file:getFilename() or "")
end

-- ---------------------------------------------------------------- lifecycle

function love.load()
  love.math.setRandomSeed(os.time())
  for _ = 1, 8 do love.math.random() end
  love.keyboard.setKeyRepeat(true)
  -- Text input stays off until a preset name is being typed, so the on-screen
  -- keyboard only appears then.
  if love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, false) end
  ui.computeLayout()
  tray.resetViews()
  loadSession()
  calc.ensureSolved()
  hooks.load()
end

function love.quit()
  saveSession()
end

-- Android can stop the app without a quit, but it always drops focus first.
-- The held control is dropped too: a notification shade pulled down
-- mid-press swallows the release, and a stepper left held would keep
-- counting on return.
function love.focus(focused)
  if not focused then
    ui.press = nil
    saveSession()
  end
end

-- For the test drivers: the same entry points the input handlers use.
app.activate, app.step, app.showTab = activate, step, showTab
