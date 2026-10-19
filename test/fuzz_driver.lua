--[[
  fuzz_driver.lua -- replaces game/hooks.lua for test/fuzz.py.

  Drives the app's own input handlers -- love.touchpressed, love.mousepressed
  and the rest, in window units -- with thousands of random presses, holds,
  drags, wheel turns, keys and typed text, and checks every invariant after
  each frame. Presses land on a random registered control most of the time
  and anywhere at random the rest. Fingers and the mouse are mixed, and
  fingers sometimes come with the istouch mouse events SDL adds to them.
  Typed text covers accented letters, the session file's delimiters,
  multi-code-point emoji and malformed UTF-8.

  The input comes from a fixed seed. The app still runs on real frame time,
  so two runs differ a little in what that input reaches; the coverage floors
  at the end sit well below what a run gets to, so passing them is not luck.
--]]

local FRAMES = FRAMES_HERE
local PROTO = "PROTO_HERE"

io.stdout:setvbuf("no")

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local session = require("session")
local tray = require("tray")
local sheet = require("sheet")
local calc = require("calc")
local store = require("store")
local partysheet = require("partysheet")

local hooks = {}
local fz = love.math.newRandomGenerator(20260926)
local frameNo = 0
local fx, fy = 0, 0
local finger = nil

local function r01() return fz:random() end
local function pickInt(n) return fz:random(1, n) end

local function fail(msg)
  print("FUZZ FAIL at frame " .. frameNo .. ": " .. msg)
  print(store.encodeState(app.st))
  os.exit(1)
end

function love.errorhandler(msg)
  print("FUZZ FAIL at frame " .. frameNo .. ": error " .. debug.traceback(tostring(msg), 2))
  os.exit(1)
end

local function need(c, msg) if not c then fail(msg) end end

local note = nil
function hooks.note(id, arg) note = id .. "/" .. tostring(arg) end

-- ---------------------------------------------------------------- invariants

local function validUtf8(s)
  local out = {}
  for cp in rules.codepoints(s) do out[#out + 1] = rules.encodeCodepoint(cp) end
  return table.concat(out) == s
end

local function attackOk(a, who)
  need(a.bonus >= rules.BONUS_MIN and a.bonus <= rules.BONUS_MAX, who .. " bonus " .. a.bonus)
  need(a.mod >= rules.MOD_MIN and a.mod <= rules.MOD_MAX, who .. " mod " .. a.mod)
  need(a.attacks >= rules.ATTACKS_MIN and a.attacks <= rules.ATTACKS_MAX, who .. " attacks")
  need(a.crit >= 1 and a.crit <= #rules.CRIT_MINS, who .. " crit")
  need(#a.groups >= 1 and #a.groups <= rules.MAX_GROUPS, who .. " groups")
  for _, g in ipairs(a.groups) do need(rules.isSize(g.d) and g.n >= 1, who .. " group") end
  need(rules.diceCount(a) <= rules.MAX_DICE, who .. " dice")
end

local function invariants()
  local st = app.st
  local a = st.attack
  -- The party: never empty, at most twelve, names unique ignoring case and
  -- clean, every character's presets and attack inside the limits.
  need(#st.party >= 1 and #st.party <= store.MAX_CHARACTERS, "party of " .. #st.party)
  need(st.current >= 1 and st.current <= #st.party, "current " .. st.current)
  need(rawget(st, "attack") == nil and rawget(st, "presets") == nil and rawget(st, "active") == nil,
       "the working attack was stored on the state instead of the character")
  local names = {}
  for i, c in ipairs(st.party) do
    need(c.name ~= "" and c.name == rules.sanitizeName(c.name) and rules.length(c.name) <= rules.NAME_MAX,
         "character name [" .. c.name .. "]")
    need(not names[c.name:lower()], "two characters called " .. c.name)
    names[c.name:lower()] = true
    need(rules.length(c.note) <= store.NOTE_MAX and validUtf8(c.note), "note of " .. c.name)
    need(c.color >= 1 and c.color <= #store.COLORS, "colour of " .. c.name)
    need(#c.presets <= rules.MAX_PRESETS and c.active >= 0 and c.active <= #c.presets, "presets of " .. c.name)
    attackOk(c.attack, c.name)
    for _, pr in ipairs(c.presets) do attackOk(pr.attack, c.name .. "/" .. pr.name) end
  end
  local q = app.party
  need(q.mode == "list" or q.mode == "edit" or q.mode == "import", "party mode " .. tostring(q.mode))
  if not q.open then need(q.mode == "list", "party sheet closed in " .. q.mode .. " mode") end
  need(validUtf8(q.nameBuf) and rules.length(q.nameBuf) <= rules.NAME_MAX, "party name field")
  need(q.confirmDelete >= 0 and q.confirmDelete <= #st.party, "party confirmDelete")
  need(not (app.sheet.open and q.open), "both sheets open")
  need(a.bonus >= rules.BONUS_MIN and a.bonus <= rules.BONUS_MAX, "bonus " .. a.bonus)
  need(a.mod >= rules.MOD_MIN and a.mod <= rules.MOD_MAX, "mod " .. a.mod)
  need(a.attacks >= rules.ATTACKS_MIN and a.attacks <= rules.ATTACKS_MAX, "attacks " .. a.attacks)
  need(a.crit >= 1 and a.crit <= #rules.CRIT_MINS, "crit " .. a.crit)
  need(#a.groups >= 1 and #a.groups <= rules.MAX_GROUPS, "groups " .. #a.groups)
  for _, g in ipairs(a.groups) do need(rules.isSize(g.d) and g.n >= 1, "group " .. g.n .. "d" .. g.d) end
  need(rules.diceCount(a) <= rules.MAX_DICE, "attack dice " .. rules.diceCount(a))
  need(st.ac >= rules.AC_MIN and st.ac <= rules.AC_MAX, "ac " .. st.ac)
  need(st.checkDc >= 0 and st.checkDc <= rules.DC_MAX, "dc " .. st.checkDc)
  need(st.checkMod >= rules.CHECK_MOD_MIN and st.checkMod <= rules.CHECK_MOD_MAX, "check mod " .. st.checkMod)
  need(st.tab >= 1 and st.tab <= 4 and st.attackSub >= 1 and st.attackSub <= 2, "tab " .. st.tab .. "/" .. st.attackSub)
  need(st.palIdx >= 1 and st.palIdx <= 11, "palette " .. st.palIdx)
  need(st.chart >= 1 and st.chart <= 2 and st.rollMode >= 1 and st.rollMode <= 3, "chart or mode")

  calc.ensureSolved()
  local mass = 0
  for v = 0, app.sol.dist.n do mass = mass + app.sol.dist[v] end
  need(math.abs(mass - 1) < 1e-9, "distribution mass " .. mass)

  need(#st.presets <= rules.MAX_PRESETS, "presets " .. #st.presets)
  need(st.active >= 0 and st.active <= #st.presets, "active " .. st.active)
  for _, p in ipairs(st.presets) do
    need(p.name ~= "" and p.name == rules.sanitizeName(p.name), "unsanitised name [" .. p.name .. "]")
    need(rules.diceCount(p.attack) <= rules.MAX_DICE, "preset dice")
  end
  local s = app.sheet
  need(s.editing == false or s.editing == "new" or (type(s.editing) == "number" and st.presets[s.editing] ~= nil),
       "editing " .. tostring(s.editing))
  need(s.confirmDelete >= 0 and s.confirmDelete <= #st.presets, "confirmDelete " .. s.confirmDelete)
  if not s.open then need(s.editing == false, "editing with the sheet closed") end
  need(validUtf8(s.nameBuf), "the name field holds malformed UTF-8")
  need(rules.length(s.nameBuf) <= rules.NAME_MAX, "the name field is " .. rules.length(s.nameBuf) .. " characters")
  -- The on-screen keyboard is up exactly while a name is being typed.
  local typing = sheet.isEditing() or partysheet.isEditing()
  need(love.keyboard.hasTextInput() == typing,
       "text input " .. tostring(love.keyboard.hasTextInput()) .. " while typing is " .. tostring(typing))

  local ids = {}
  for _, h in ipairs(ui.hits) do
    local k = h.id .. "/" .. tostring(h.arg)
    need(not ids[k], "two controls share the id " .. k)
    ids[k] = true
  end

  -- Whatever state the input produced must survive its own save and load.
  local text = store.encodeState(st)
  local copy = store.decodeState(text)
  need(copy ~= nil, "state will not decode")
  need(copy and store.encodeState(copy) == text, "round trip changed the state")
end

-- ---------------------------------------------------------------- input

local TYPED = { "a", "Z", " ", "ã", "ç", "é", "|", "=", "+", "1", "-", "(", "⚔",
                "🗡️", "👍🏽", "日本", "\xC3", "\xFF", "a\xE2\x82",
                -- An IME or a paste can deliver a whole phrase at once.
                "Longsword of the Seventh Circle", "Ação ⚔ Ação ⚔ Ação ⚔ Ação ⚔ Ação" }

local function w(dx, dy) return dx * ui.S, dy * ui.S end

local function pressAt(dx, dy)
  fx, fy = dx, dy
  local wx, wy = w(dx, dy)
  if r01() < 0.5 then
    finger = (finger or 0) + 1 + pickInt(1000)
    love.touchpressed(finger, wx, wy, 0, 0, 1)
    if r01() < 0.7 then love.mousepressed(wx, wy, 1, true, 1) end   -- SDL's copy, ignored
  else
    finger = nil
    love.mousepressed(wx, wy, 1, false, 1)
  end
end

local function moveTo(dx, dy)
  fx, fy = dx, dy
  local wx, wy = w(dx, dy)
  if finger then
    love.touchmoved(finger, wx, wy, 0, 0, 1)
    love.mousemoved(wx, wy, 0, 0, true)
  else
    love.mousemoved(wx, wy, 0, 0, false)
  end
end

local function release()
  local wx, wy = w(fx, fy)
  if finger then
    love.touchreleased(finger, wx, wy, 0, 0, 1)
    love.mousereleased(wx, wy, 1, true, 1)
  else
    love.mousereleased(wx, wy, 1, false, 1)
  end
end

local function key(k) love.keypressed(k, k, false) end

-- What the clipboard may hold when Paste is tapped: the app's own files,
-- the web app's, a session.txt, and things that are none of them.
local function clipboardFile()
  local r = r01()
  if r < 0.25 then return store.characterFile(app.st.party[pickInt(#app.st.party)]) end
  if r < 0.45 then return store.partyFile(app.st) end
  if r < 0.55 then return store.partyFile(store.fresh()) end
  if r < 0.65 then return io.open(PROTO, "rb"):read("*a") end
  local junk = { "", "hello", "{", '{"format":"dice-and-damage-party","version":1,"characters":[{"name":"\\u0000|="}]}',
                 '{"format":"dice-and-damage-character","version":1,"character":{"name":"' .. string.rep("W", 60) .. '","color":-3,"presets":[' ..
                   string.rep('{"name":"x","attack":{"dice":"9d20+9d20"}},', 12) .. '{"name":"y","attack":{"dice":"1d4"}}]}}',
                 '{"format":"dice-and-damage-party","version":1,"characters":[' .. string.rep('{"name":"Clone"},', 14) .. '{"name":"Last"}]}',
                 string.rep("[", 50), "v=1\npreset=Only|1|1d6|0|1|0\n" }
  local text = junk[pickInt(#junk)]
  if r01() < 0.3 then text = text:sub(1, pickInt(#text + 1) - 1) end     -- cut short
  return text
end

local function randomKey()
  if partysheet.isEditing() then
    local r = r01()
    if r < 0.72 then love.textinput(TYPED[pickInt(#TYPED)])
    elseif r < 0.84 then key("backspace")
    elseif r < 0.95 then key("return")
    else key("escape") end
    return
  end
  if sheet.isEditing() then
    local r = r01()
    if r < 0.72 then love.textinput(TYPED[pickInt(#TYPED)])
    elseif r < 0.84 then key("backspace")
    elseif r < 0.95 then key("return")
    else key("escape") end
    return
  end
  local hot = { "1", "2", "3", "4", "c", "p", "n", "a", "v", "space", "r", "k", "[", "]" }
  key(hot[pickInt(#hot)])
  if app.sheet.open and r01() < 0.1 then key("escape") end
end

--- Taps a random control registered after index `from`.
local function tapFrom(from, quick)
  if from >= #ui.hits then return end
  local t = ui.hits[from + pickInt(#ui.hits - from)]
  pressAt(t.x + r01() * t.w, t.y + r01() * t.h)
  if quick then release() end
end

local function sheetFrom()
  for k, h in ipairs(ui.hits) do if h.id == "backdrop" or h.id == "qback" then return k end end
  return 0
end

local function act()
  if ui.press then
    local r = r01()
    if r < 0.30 then release()
    elseif r < 0.50 then moveTo(fx + r01() * 40 - 20, fy + r01() * 60 - 30) end
    return                                             -- otherwise keep holding
  end
  local r = r01()

  -- With the sheet open the fuzzer works the sheet: its own controls almost
  -- always, the backdrop and the keys that close it rarely. Otherwise random
  -- taps close it within a few frames and it never saves or deletes a thing.
  if app.party.open then
    if partysheet.isEditing() and r < 0.45 then randomKey() return end
    if r < 0.10 then
      pcall(love.system.setClipboardText, clipboardFile())
      partysheet.paste()
      return
    end
    if r < 0.95 then tapFrom(sheetFrom(), r01() < 0.85) return end
    if r < 0.98 then tapFrom(0, true) return end
    key("escape")
    return
  end
  if app.sheet.open then
    if sheet.isEditing() and r < 0.45 then randomKey() return end
    if r < 0.95 then tapFrom(sheetFrom(), r01() < 0.85) return end
    if r < 0.98 then tapFrom(0, true) return end       -- anything, backdrop included
    key("escape")
    return
  end

  if r < 0.04 then
    local want = r01() < 0.5 and "presets" or "party"
    local h
    for _, t in ipairs(ui.hits) do if t.id == want then h = t end end
    if h then pressAt(h.x + 5, h.y + 5) release() end
  elseif r < 0.66 then
    tapFrom(0, r01() < 0.75)                           -- most taps are quick
  elseif r < 0.80 then
    pressAt(r01() * ui.VW, r01() * ui.VH)
  elseif r < 0.88 then
    love.wheelmoved(0, pickInt(7) - 4)
  else
    randomKey()
  end
end

-- ---------------------------------------------------------------- coverage

local tabsSeen, subsSeen = {}, {}
local sheetOpens, saves, deletes, renames, renameStarts, scrubs, edits, typed = 0, 0, 0, 0, 0, 0, 0, 0
local calcToAttack, attackToDamage, critHandoffs = 0, 0, 0
local newAttacks, switches, imports, partyMax = 0, 0, 0, 0
local lastCount, lastNames, lastEditing, wasOpen = -1, "", false, false
local tabBefore, attackBefore, damageBefore = 1, nil, nil

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function coverage()
  local st = app.st
  partyMax = math.max(partyMax, #st.party)
  tabsSeen[st.tab] = true
  if st.tab == app.ATTACK then subsSeen[st.attackSub] = true end
  if app.calc.scrub >= 0 then scrubs = scrubs + 1 end
  if session.edited(st) then edits = edits + 1 end
  local n = #st.presets
  if lastCount >= 0 then
    if n > lastCount then saves = saves + 1 end
    if n < lastCount then deletes = deletes + 1 end
  end
  local names = {}
  for _, p in ipairs(st.presets) do names[#names + 1] = p.name end
  local joined = table.concat(names, "\n")
  if n == lastCount and joined ~= lastNames then renames = renames + 1 end
  lastCount, lastNames = n, joined
  if app.sheet.open and not wasOpen then sheetOpens = sheetOpens + 1 end
  local e = app.sheet.editing
  if type(e) == "number" and lastEditing ~= e then renameStarts = renameStarts + 1 end
  if app.sheet.nameBuf:find("[\128-\255]") then typed = typed + 1 end
  lastEditing, wasOpen = e, app.sheet.open
end

-- ---------------------------------------------------------------- loop

function hooks.load()
  -- The app's dice are seeded from the clock. The fuzzer supplies its own,
  -- from its fixed seed, so a run is repeatable -- and lands on the top face
  -- a quarter of the time, so crits and their hand-off come up often.
  app.rng = function(lo, hi) if r01() < 0.25 then return hi end return fz:random(lo, hi) end
  app.touchWatchdog = false          -- these fingers are not ones SDL can see
end

-- Input goes in where LOVE delivers events: before the update.
function hooks.update(dt)
  frameNo = frameNo + 1
  if frameNo < 3 then return end
  if frameNo % 1000 == 0 then print("FUZZ progress " .. frameNo) end
  act()

  local st = app.st
  -- The two hand-offs: whatever started them, they must land where they say.
  if note == "roll/0" and tabBefore == app.CALC then
    calcToAttack = calcToAttack + 1
    local d = app.views.attack.d20
    need(st.tab == app.ATTACK and st.attackSub == 1 and d ~= nil and d ~= attackBefore,
         "Roll attack on the Calculator did not switch to the Attack tab and roll")
    need(d.mod == st.attack.bonus and d.target == st.ac, "Roll attack rolled with a bonus or AC other than the Calculator's")
  end
  if note == "rollatk/0" then
    newAttacks = newAttacks + 1
    local d = app.views.attack.d20
    need(st.tab == app.ATTACK and st.attackSub == 1 and d ~= nil and d ~= attackBefore,
         "New attack did not switch to the Attack tab and roll")
    need(d.mod == st.attack.bonus and d.target == st.ac, "New attack rolled with a bonus or AC other than the attack's")
  end
  if note and note:sub(1, 6) == "qpick/" then switches = switches + 1 end
  if note == "qadd/0" or note == "qreplace/0" or note == "qparty/0" then imports = imports + 1 end
  if note == "rolldmg/0" then
    attackToDamage = attackToDamage + 1
    local crit = app.views.attack.d20 ~= nil and app.views.attack.d20.crit
    if crit then critHandoffs = critHandoffs + 1 end
    local d = app.views.damage.dmg
    need(st.tab == app.DAMAGE and d ~= nil and d ~= damageBefore,
         "Damage on the Attack tab did not switch to the Damage tab and roll")
    need(d.doubled == crit and st.doubleDice == crit, "Damage doubled " .. tostring(d.doubled) .. " after a crit " .. tostring(crit))
    need(#d.dice == rules.diceCount(st.attack) * (crit and 2 or 1),
         "Damage rolled " .. #d.dice .. " dice for an attack with " .. rules.diceCount(st.attack))
  end
  note = nil
  tabBefore, attackBefore, damageBefore = st.tab, app.views.attack.d20, app.views.damage.dmg

  -- Keep the animations moving faster than real time, so rolls finish
  -- between taps.
  for _, v in ipairs(tray.allViews()) do
    if v.d20Anim then v.d20Anim.t = v.d20Anim.t + 0.1 end
    if v.dmgAnim then v.dmgAnim.t = v.dmgAnim.t + 0.1 end
  end
end

-- Invariants are checked on the frame just drawn, so the ids are this frame's.
function hooks.frame()
  if frameNo < 3 then return end
  invariants()
  coverage()
  if frameNo >= FRAMES then
    print(string.format("FUZZ %d frames: tabs %d, attack subs %d, sheet opened %d, saves %d, deletes %d, "
      .. "renames %d of %d started, calculator->attack %d, attack->damage %d (%d crits), "
      .. "scrub frames %d, edited frames %d, frames with non-ASCII names %d",
      FRAMES, count(tabsSeen), count(subsSeen), sheetOpens, saves, deletes, renames, renameStarts,
      calcToAttack, attackToDamage, critHandoffs, scrubs, edits, typed))
    need(count(tabsSeen) == 4 and count(subsSeen) == 2, "did not reach every tab")
    need(sheetOpens > 5 and saves > 0 and deletes > 0 and renames > 0, "barely used presets")
    need(calcToAttack > 5 and attackToDamage > 5 and critHandoffs > 0, "barely used the hand-offs")
    need(edits > 0 and scrubs > 0 and typed > 0, "never edited a preset, scrubbed or typed beyond ASCII")
    print(string.format("FUZZ party: new attacks from Damage %d, character switches %d, imports %d, largest party %d",
      newAttacks, switches, imports, partyMax))
    need(newAttacks > 3 and switches > 3 and imports > 3, "barely used the party")
    print("FUZZ all invariants held")
    love.event.quit()
  end
end

return hooks
