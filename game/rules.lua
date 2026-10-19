--[[
  rules.lua -- what an attack is, and the limits every control respects.

  Plain Lua, no LOVE calls, so test/logic.lua runs it under LuaJIT directly.
  A line-for-line port of Rules.pde in the Processing prototype.

  An attack is exactly what a preset stores: to-hit bonus, damage dice,
  damage bonus, attacks per round and crit range. Its dice and damage bonus
  are what the Damage tab rolls, so the Calculator and the Damage tab edit the
  same values under the same limits. Everything that changes from fight to
  fight -- enemy AC, advantage, the HP you are trying to take off -- is
  situation, lives in the app state, and is never part of a preset.

  Indices are 1-based here, as Lua expects. The session file keeps the
  prototype's 0-based numbers; session.lua converts at the boundary.

    attack = { bonus, groups = { {n=, d=}, ... }, mod, attacks, crit }
--]]

local rules = {}

rules.DIE_SIZES   = { 4, 6, 8, 10, 12, 20 }
rules.CRIT_MINS   = { 20, 19, 18 }
rules.CRIT_LABELS = { "20", "19–20", "18–20" }

rules.DISADVANTAGE, rules.NORMAL, rules.ADVANTAGE = 1, 2, 3

-- Fifteen dice, doubled on a crit, is thirty: the most the tray can draw at
-- once, so a crit can never overflow it.
rules.MAX_GROUPS  = 5
rules.MAX_DICE    = 15
rules.BONUS_MIN, rules.BONUS_MAX     = -5, 20
rules.MOD_MIN, rules.MOD_MAX         = -10, 50
rules.ATTACKS_MIN, rules.ATTACKS_MAX = 1, 4

rules.AC_MIN, rules.AC_MAX = 1, 40
rules.CHECK_MOD_MIN, rules.CHECK_MOD_MAX = -10, 30
rules.DC_MAX = 40                     -- 0 means "do not judge the roll"

rules.MAX_PRESETS = 8
rules.NAME_MAX    = 24                -- characters, not bytes

function rules.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function rules.isSize(d)
  for _, s in ipairs(rules.DIE_SIZES) do if s == d then return true end end
  return false
end

--- Next die size in the cycle, d20 wrapping back to d4.
function rules.nextSize(d)
  for i, s in ipairs(rules.DIE_SIZES) do
    if s == d then return rules.DIE_SIZES[i % #rules.DIE_SIZES + 1] end
  end
  return rules.DIE_SIZES[1]
end

function rules.count(groups)
  local n = 0
  for _, g in ipairs(groups) do n = n + g.n end
  return n
end

--- "2d8 + 1d6", doubled counts on a crit.
function rules.diceText(groups, doubled)
  if #groups == 0 then return "no dice" end
  local parts = {}
  for _, g in ipairs(groups) do
    parts[#parts + 1] = (doubled and g.n * 2 or g.n) .. "d" .. g.d
  end
  return table.concat(parts, " + ")
end

function rules.modText(mod)
  if mod > 0 then return " + " .. mod end
  if mod < 0 then return " − " .. -mod end
  return ""
end

function rules.signed(v)
  if v > 0 then return "+" .. v end
  if v < 0 then return "−" .. -v end
  return "0"
end

-- ---------------------------------------------------------------- utf-8
-- LuaJIT has no utf8 library, and names must be cut by character, never by
-- byte. These decode strictly: an invalid byte, an overlong form or an
-- encoded surrogate is skipped, so whatever a hand-edited session file holds,
-- what comes out is always valid UTF-8.

--- Iterates the code points of s, skipping anything malformed.
function rules.codepoints(s)
  local i, len = 1, #s
  return function()
    while i <= len do
      local c = s:byte(i)
      local n, cp, min
      if c < 0x80 then n, cp, min = 0, c, 0
      elseif c >= 0xC2 and c <= 0xDF then n, cp, min = 1, c - 0xC0, 0x80
      elseif c >= 0xE0 and c <= 0xEF then n, cp, min = 2, c - 0xE0, 0x800
      elseif c >= 0xF0 and c <= 0xF4 then n, cp, min = 3, c - 0xF0, 0x10000
      else n = -1 end
      if n >= 0 and i + n <= len then
        local ok = true
        for k = 1, n do
          local b = s:byte(i + k)
          if b < 0x80 or b > 0xBF then ok = false break end
          cp = cp * 64 + (b - 0x80)
        end
        if ok and cp >= min and cp <= 0x10FFFF and not (cp >= 0xD800 and cp <= 0xDFFF) then
          i = i + n + 1
          return cp
        end
      end
      i = i + 1                        -- a bad byte: skip it and resynchronise
    end
  end
end

function rules.encodeCodepoint(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
                     0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function rules.length(s)
  local n = 0
  for _ in rules.codepoints(s) do n = n + 1 end
  return n
end

--- s without its last character.
function rules.dropLast(s)
  local cps = {}
  for cp in rules.codepoints(s) do cps[#cps + 1] = cp end
  cps[#cps] = nil
  local out = {}
  for k, cp in ipairs(cps) do out[k] = rules.encodeCodepoint(cp) end
  return table.concat(out)
end

-- The code points Java's Character.isWhitespace calls whitespace, above the
-- control range (which is removed outright before this is asked).
local SPACE = { [32] = true, [0x1680] = true, [0x2028] = true, [0x2029] = true,
                [0x205F] = true, [0x3000] = true }
for cp = 0x2000, 0x200A do if cp ~= 0x2007 then SPACE[cp] = true end end

--- A preset name that can always be written, read back and drawn. Control
--- characters go, so do the two characters the session format uses as
--- delimiters, whitespace collapses, and the result is cut to NAME_MAX
--- characters.
function rules.sanitizeName(s, max)
  if type(s) ~= "string" then return "" end
  max = max or rules.NAME_MAX
  local out, kept, space = {}, 0, false
  for cp in rules.codepoints(s) do
    if kept >= max then break end
    if cp < 32 or cp == 127 or cp == 124 or cp == 61 then
      -- control characters, "|" and "=": dropped
    elseif SPACE[cp] then
      space = #out > 0
    else
      if space then
        if kept + 1 >= max then break end
        out[#out + 1] = " "
        kept = kept + 1
        space = false
      end
      out[#out + 1] = rules.encodeCodepoint(cp)
      kept = kept + 1
    end
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------- dice specs

--- Parses "2d8+1d6" into groups; anything malformed is skipped.
function rules.parseDice(spec, maxGroups, maxDice)
  local out = {}
  if type(spec) ~= "string" then return out end
  for part in spec:gmatch("[^+]+") do
    local n, d = part:match("^%s*(%d+)%s*d%s*(%d+)%s*$")
    n, d = tonumber(n), tonumber(d)
    if n and d and rules.isSize(d) and n >= 1 and n <= maxDice then
      if #out >= maxGroups then break end
      out[#out + 1] = { n = n, d = d }
    end
  end
  if rules.count(out) > maxDice then out = {} end
  return out
end

function rules.encodeDice(groups)
  local parts = {}
  for _, g in ipairs(groups) do parts[#parts + 1] = g.n .. "d" .. g.d end
  return table.concat(parts, "+")
end

-- ---------------------------------------------------------------- attacks

function rules.newAttack(bonus, dice, mod, attacks, crit)
  local a = {
    bonus = bonus or 5,
    groups = rules.parseDice(dice or "1d8", rules.MAX_GROUPS, rules.MAX_DICE),
    mod = mod or 3,
    attacks = attacks or 1,
    crit = crit or 1,
  }
  if #a.groups == 0 then a.groups = { { n = 1, d = 8 } } end
  rules.clampAttack(a)
  return a
end

function rules.copyAttack(a)
  local g = {}
  for i, x in ipairs(a.groups) do g[i] = { n = x.n, d = x.d } end
  return { bonus = a.bonus, groups = g, mod = a.mod, attacks = a.attacks, crit = a.crit }
end

function rules.sameAttack(a, b)
  if not a or not b then return false end
  if a.bonus ~= b.bonus or a.mod ~= b.mod or a.attacks ~= b.attacks
     or a.crit ~= b.crit or #a.groups ~= #b.groups then return false end
  for i, g in ipairs(a.groups) do
    if g.n ~= b.groups[i].n or g.d ~= b.groups[i].d then return false end
  end
  return true
end

function rules.critMin(a) return rules.CRIT_MINS[a.crit] end
function rules.diceCount(a) return rules.count(a.groups) end
function rules.room(a) return rules.MAX_DICE - rules.count(a.groups) end

function rules.damageText(a, doubled)
  return rules.diceText(a.groups, doubled) .. rules.modText(a.mod)
end

--- One line for the preset bar and the preset list.
function rules.summary(a)
  local s = rules.signed(a.bonus) .. " to hit, " .. rules.damageText(a, false)
  if a.attacks > 1 then s = s .. ", " .. a.attacks .. " attacks" end
  if a.crit > 1 then s = s .. ", crit " .. rules.CRIT_LABELS[a.crit] end
  return s
end

--- Brings every field inside the limits the controls enforce.
function rules.clampAttack(a)
  local c = rules.clamp
  a.bonus   = c(a.bonus, rules.BONUS_MIN, rules.BONUS_MAX)
  a.mod     = c(a.mod, rules.MOD_MIN, rules.MOD_MAX)
  a.attacks = c(a.attacks, rules.ATTACKS_MIN, rules.ATTACKS_MAX)
  a.crit    = c(a.crit, 1, #rules.CRIT_MINS)
  while #a.groups > rules.MAX_GROUPS do table.remove(a.groups) end
  for _, g in ipairs(a.groups) do
    if not rules.isSize(g.d) then g.d = 8 end
    g.n = c(g.n, 1, rules.MAX_DICE)
  end
  while rules.count(a.groups) > rules.MAX_DICE do
    local last = a.groups[#a.groups]
    if last.n > 1 then last.n = last.n - 1 else table.remove(a.groups) end
  end
  if #a.groups == 0 then a.groups = { { n = 1, d = 8 } } end
  return a
end

return rules
