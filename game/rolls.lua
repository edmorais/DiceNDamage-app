--[[
  rolls.lua -- what a roll is and how one is made.

  Plain Lua; a port of Rolls.pde. The random source is passed in, with the
  signature rng(lo, hi) inclusive at both ends, so a test can hand it a
  scripted sequence and pin down every branch, and so main.lua stays in charge
  of seeding. The rules are the ones damage.lua enumerates; test/logic.lua
  builds whole rounds from attack() and damage(), rolls a few hundred
  thousand, and checks the two agree.

    die    = { sides, value, kept, max, min }
    d20    = { dice, keep, natural, mod, total, crit, fumble,
               isAttack, judged, target, success }
    damage = { dice, sum, mod, total, doubled, allMax, percent }
--]]

local rules = require("rules")

local rolls = {}

local function die(sides, value)
  return { sides = sides, value = value, kept = true, max = false, min = false }
end

--- Keeps the lower of two d20s for disadvantage, rolls one for a normal
--- roll, keeps the higher for advantage.
function rolls.d20(rng, mod, mode, critMin)
  local r = {}
  local a = rng(1, 20)
  if mode == rules.NORMAL then
    r.dice, r.keep = { die(20, a) }, 1
  else
    local b = rng(1, 20)
    r.dice, r.keep = { die(20, a), die(20, b) }, 1
    if mode == rules.ADVANTAGE and b > a then r.keep = 2 end
    if mode == rules.DISADVANTAGE and b < a then r.keep = 2 end
  end
  for i, d in ipairs(r.dice) do
    d.kept = (i == r.keep)
    d.max = d.kept and d.value >= critMin
    d.min = d.kept and d.value == 1
  end
  r.natural = r.dice[r.keep].value
  r.mod = mod
  r.total = r.natural + mod
  r.crit = r.natural >= critMin
  r.fumble = r.natural == 1
  return r
end

function rolls.hits(r, ac)
  if r.crit then return true end
  if r.fumble then return false end
  return r.total >= ac
end

--- Attack roll against an AC: a crit always hits, a natural 1 never does.
--- The AC is frozen into the roll, so changing it afterwards does not
--- rewrite what already happened.
function rolls.attack(rng, bonus, mode, critMin, ac)
  local r = rolls.d20(rng, bonus, mode, critMin)
  r.isAttack, r.judged, r.target = true, true, ac
  r.success = rolls.hits(r, ac)
  return r
end

--- Ability check or save. No crits on checks in 5e, but the 20 and the 1 are
--- still called out, so critMin is 20 and success is plain total >= DC.
function rolls.check(rng, mod, mode, dc)
  local r = rolls.d20(rng, mod, mode, 20)
  r.isAttack, r.judged, r.target = false, dc > 0, dc
  r.success = dc > 0 and r.total >= dc
  return r
end

function rolls.damage(rng, groups, mod, doubled)
  local r = { dice = {}, sum = 0, mod = mod, doubled = doubled and true or false }
  for _, g in ipairs(groups) do
    for _ = 1, doubled and g.n * 2 or g.n do
      local v = rng(1, g.d)
      r.sum = r.sum + v
      local d = die(g.d, v)
      d.max, d.min = v == g.d, v == 1
      r.dice[#r.dice + 1] = d
    end
  end
  r.total = r.sum + mod
  r.allMax = #r.dice > 0
  for _, d in ipairs(r.dice) do
    if not d.max then r.allMax = false break end
  end
  return r
end

function rolls.percent(rng)
  local v = rng(1, 100)
  local d = die(100, v)
  d.max, d.min = v == 100, v == 1
  return { dice = { d }, sum = v, mod = 0, total = v, doubled = false,
           allMax = d.max, percent = true }
end

return rolls
