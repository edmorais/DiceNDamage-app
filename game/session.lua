--[[
  session.lua -- everything that survives a relaunch, and the presets.

  Plain Lua; a port of Session.pde. encode and decode work on lists of lines
  and main.lua does the file IO, so the round trip is testable without LOVE.

  The file format is the Processing prototype's, byte for byte, so a
  session.txt written by either loads in the other. It is flat key=value, one
  per line, UTF-8. Presets are one line each,
  `preset=name|bonus|dice|mod|attacks|crit`, in list order. It is parsed
  rather than executed and every value is range-checked on the way in, so a
  truncated or hand-edited file can only be ignored, never obeyed. A bad
  preset line is dropped on its own and the rest survive.

  The prototype counted from 0 -- tab=0 is the Calculator, active=-1 is no
  preset -- and Lua counts from 1. The file keeps the prototype's numbers;
  this module is the only place that knows, converting both ways.
--]]

local rules = require("rules")

local session = {}
session.VERSION = "1"

--- The state before any file is read: three worked examples, the first one
--- loaded.
function session.fresh()
  local s = {
    attack = nil,
    -- The situation: one copy, read by the Calculator and the Attack tab.
    ac = 15, rollMode = rules.NORMAL, targetHp = 20,
    -- Ability checks, kept apart so a Dex check never edits the attack.
    checkMod = 3, checkDc = 0,
    -- The Damage tab's crit toggle; the Attack tab's Damage button sets it.
    doubleDice = false,
    -- Interface.
    tab = 1, attackSub = 1, palIdx = 1, chart = 1, showCcdf = true,
    presets = {
      { name = "Longsword",               attack = rules.newAttack(7, "1d8", 4, 2, 1) },
      { name = "Rapier and Sneak Attack", attack = rules.newAttack(7, "1d8+3d6", 4, 1, 1) },
      { name = "Champion greatsword",     attack = rules.newAttack(8, "2d6", 5, 2, 2) },
    },
    active = 1,                     -- the preset the working attack came from; 0 for none
  }
  s.attack = rules.copyAttack(s.presets[1].attack)
  return s
end

function session.edited(s)
  local p = s.presets[s.active]
  return p ~= nil and not rules.sameAttack(p.attack, s.attack)
end

function session.encode(s)
  local a = s.attack
  local out = {
    "v=" .. session.VERSION,
    "bonus=" .. a.bonus,
    "dice=" .. rules.encodeDice(a.groups),
    "mod=" .. a.mod,
    "attacks=" .. a.attacks,
    "crit=" .. (a.crit - 1),
    "ac=" .. s.ac,
    "mode=" .. (s.rollMode - 1),
    "hp=" .. s.targetHp,
    "checkmod=" .. s.checkMod,
    "checkdc=" .. s.checkDc,
    "double=" .. (s.doubleDice and 1 or 0),
    "tab=" .. (s.tab - 1),
    "sub=" .. (s.attackSub - 1),
    "pal=" .. (s.palIdx - 1),
    "chart=" .. (s.chart - 1),
    "ccdf=" .. (s.showCcdf and 1 or 0),
    "active=" .. (s.active - 1),
  }
  for _, p in ipairs(s.presets) do
    local pa = p.attack
    out[#out + 1] = "preset=" .. rules.sanitizeName(p.name) .. "|" .. pa.bonus .. "|"
      .. rules.encodeDice(pa.groups) .. "|" .. pa.mod .. "|" .. pa.attacks .. "|" .. (pa.crit - 1)
  end
  return out
end

function session.joined(s)
  return table.concat(session.encode(s), "\n")
end

--- A whole number, as Java's Integer.parseInt reads one; nil otherwise.
local function whole(v)
  if type(v) ~= "string" then return nil end
  local n = v:match("^%s*([%+%-]?%d+)%s*$")
  return n and tonumber(n) or nil
end

local function field(kv, key, lo, hi, fallback)
  local n = whole(kv[key])
  if not n then return fallback end
  return rules.clamp(n, lo, hi)
end

function session.parsePreset(v)
  local f = {}
  for part in (v .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
  if #f ~= 6 then return nil end
  local name = rules.sanitizeName(f[1])
  if name == "" then return nil end
  local bonus, mod, attacks, crit = whole(f[2]), whole(f[4]), whole(f[5]), whole(f[6])
  if not (bonus and mod and attacks and crit) then return nil end
  local g = rules.parseDice(f[3], rules.MAX_GROUPS, rules.MAX_DICE)
  if #g == 0 then return nil end
  if bonus < rules.BONUS_MIN or bonus > rules.BONUS_MAX then return nil end
  if mod < rules.MOD_MIN or mod > rules.MOD_MAX then return nil end
  if attacks < rules.ATTACKS_MIN or attacks > rules.ATTACKS_MAX then return nil end
  if crit < 0 or crit >= #rules.CRIT_MINS then return nil end
  return { name = name, attack = { bonus = bonus, groups = g, mod = mod,
                                   attacks = attacks, crit = crit + 1 } }
end

--- Applies whatever the lines validly contain onto s. False means the text
--- is not a session at all and s was left untouched.
function session.decode(lines, s)
  if type(lines) ~= "table" then return false end
  local kv, presetLines = {}, {}
  for _, line in ipairs(lines) do
    if type(line) == "string" then
      local eq = line:find("=", 1, true)
      if eq and eq > 1 then
        local k = line:sub(1, eq - 1):match("^%s*(.-)%s*$")
        local v = line:sub(eq + 1):gsub("\r", "")
        if k == "preset" then presetLines[#presetLines + 1] = v else kv[k] = v end
      end
    end
  end
  if kv.v ~= session.VERSION then return false end

  local a = s.attack
  a.bonus   = field(kv, "bonus", rules.BONUS_MIN, rules.BONUS_MAX, a.bonus)
  a.mod     = field(kv, "mod", rules.MOD_MIN, rules.MOD_MAX, a.mod)
  a.attacks = field(kv, "attacks", rules.ATTACKS_MIN, rules.ATTACKS_MAX, a.attacks)
  a.crit    = field(kv, "crit", 0, #rules.CRIT_MINS - 1, a.crit - 1) + 1
  local g = rules.parseDice(kv.dice, rules.MAX_GROUPS, rules.MAX_DICE)
  if #g > 0 then a.groups = g end

  s.ac       = field(kv, "ac", rules.AC_MIN, rules.AC_MAX, s.ac)
  s.rollMode = field(kv, "mode", 0, 2, s.rollMode - 1) + 1
  s.targetHp = field(kv, "hp", 1, 5000, s.targetHp)
  s.checkMod = field(kv, "checkmod", rules.CHECK_MOD_MIN, rules.CHECK_MOD_MAX, s.checkMod)
  s.checkDc  = field(kv, "checkdc", 0, rules.DC_MAX, s.checkDc)
  s.doubleDice = field(kv, "double", 0, 1, s.doubleDice and 1 or 0) == 1

  s.tab       = field(kv, "tab", 0, 3, s.tab - 1) + 1
  s.attackSub = field(kv, "sub", 0, 1, s.attackSub - 1) + 1
  s.palIdx    = field(kv, "pal", 0, 5, s.palIdx - 1) + 1
  s.chart     = field(kv, "chart", 0, 1, s.chart - 1) + 1
  s.showCcdf  = field(kv, "ccdf", 0, 1, s.showCcdf and 1 or 0) == 1

  -- A session that says anything about presets replaces the list outright,
  -- including with nothing: an empty list is a choice the user made.
  s.presets = {}
  for _, pl in ipairs(presetLines) do
    if #s.presets >= rules.MAX_PRESETS then break end
    local p = session.parsePreset(pl)
    if p then s.presets[#s.presets + 1] = p end
  end
  -- An index past the list is dropped, not clamped: clamping would quietly
  -- mark some other preset as the one the working attack came from.
  local act = field(kv, "active", -1, math.huge, -1)
  s.active = (act < #s.presets) and act + 1 or 0
  return true
end

--- Splits file contents into lines, as Processing's loadStrings did.
function session.lines(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end

return session
