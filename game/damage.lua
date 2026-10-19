--[[
  damage.lua -- exact probability for a D&D 5e attack routine.

  Plain Lua, nothing simulated; a port of DamageMath.pde. The twenty d20
  faces are enumerated and weighted for the roll mode, dice sums are built by
  convolution, crits double every group, and extra attacks convolve the
  single-attack distribution with itself. A natural 1 always misses, anything
  at or above the crit range always hits and crits, and damage from a hit
  never goes below zero.

  Distributions are tables indexed from 0 with the largest index in `n`, so
  d[0] .. d[d.n] are the probabilities and they sum to 1. Lua has one number
  type, a double, so the single-precision trap Processing's preprocessor set
  for the prototype does not exist here; test/logic.lua checks the sums to
  1e-12 all the same.
--]]

local rules = require("rules")

local damage = {}

--- P(kept d20 face == k), k = 1 .. 20.
function damage.faceProbs(mode)
  local f = {}
  for k = 1, 20 do
    if mode == rules.ADVANTAGE then f[k] = (2 * k - 1) / 400
    elseif mode == rules.DISADVANTAGE then f[k] = (41 - 2 * k) / 400
    else f[k] = 1 / 20 end
  end
  return f
end

--- hit, crit, miss for one attack. hit excludes crits.
function damage.hitChances(bonus, ac, mode, critMin)
  local f = damage.faceProbs(mode)
  local hit, crit, miss = 0, 0, 0
  for k = 1, 20 do
    if k >= critMin then crit = crit + f[k]
    elseif k == 1 then miss = miss + f[k]
    elseif k + bonus >= ac then hit = hit + f[k]
    else miss = miss + f[k] end
  end
  return hit, crit, miss
end

function damage.convolve(a, b)
  local r = { n = a.n + b.n }
  for i = 0, r.n do r[i] = 0 end
  for i = 0, a.n do
    local ai = a[i]
    if ai >= 1e-18 then
      for j = 0, b.n do r[i + j] = r[i + j] + ai * b[j] end
    end
  end
  return r
end

--- Distribution of the sum of every group, each count multiplied.
function damage.sumDist(groups, mult)
  local d = { [0] = 1, n = 0 }
  for _, g in ipairs(groups) do
    local die = { [0] = 0, n = g.d }
    for v = 1, g.d do die[v] = 1 / g.d end
    for _ = 1, g.n * mult do d = damage.convolve(d, die) end
  end
  return d
end

--- One attack's damage, including the mass that piles up at 0 on a miss.
function damage.attackDist(pHit, pCrit, pMiss, hitDice, critDice, mod)
  local maxD = math.max(1, critDice.n + mod)
  local d = { n = maxD }
  for i = 0, maxD do d[i] = 0 end
  d[0] = d[0] + pMiss
  for v = 0, hitDice.n do
    local p = hitDice[v]
    if p > 0 then
      local t = rules.clamp(v + mod, 0, maxD)
      d[t] = d[t] + pHit * p
    end
  end
  for v = 0, critDice.n do
    local p = critDice[v]
    if p > 0 then
      local t = rules.clamp(v + mod, 0, maxD)
      d[t] = d[t] + pCrit * p
    end
  end
  return d
end

--- Everything the Calculator shows, for one attack and situation.
function damage.solve(a, ac, mode)
  local s = {}
  s.pHit, s.pCrit, s.pMiss = damage.hitChances(a.bonus, ac, mode, rules.critMin(a))
  s.hitDice  = damage.sumDist(a.groups, 1)
  s.critDice = damage.sumDist(a.groups, 2)

  local one = damage.attackDist(s.pHit, s.pCrit, s.pMiss, s.hitDice, s.critDice, a.mod)
  local r = one
  for _ = 2, a.attacks do r = damage.convolve(r, one) end
  s.dist = r

  local ccdf, acc = { n = r.n }, 0
  for i = r.n, 0, -1 do
    acc = acc + r[i]
    ccdf[i] = math.min(1, acc)
  end
  s.ccdf = ccdf

  local mean = 0
  for i = 0, r.n do mean = mean + i * r[i] end
  local m2 = 0
  for i = 0, r.n do m2 = m2 + r[i] * (i - mean) * (i - mean) end
  s.mean, s.sd = mean, math.sqrt(m2)

  local run, best, medSet = 0, -1, false
  s.median, s.mode = 0, 0
  for i = 0, r.n do
    run = run + r[i]
    if not medSet and run >= 0.5 then s.median, medSet = i, true end
    if r[i] > best then best, s.mode = r[i], i end
  end
  return s
end

function damage.max(s) return s.dist.n end

function damage.atLeast(s, t)
  if t <= 0 then return 1 end
  if t > s.dist.n then return 0 end
  return s.ccdf[t]
end

function damage.exactly(s, t)
  if t < 0 or t > s.dist.n then return 0 end
  return s.dist[t]
end

--- Average damage of one hit, never below zero.
function damage.expectedFrom(dice, mod)
  local e = 0
  for v = 0, dice.n do e = e + dice[v] * math.max(0, v + mod) end
  return e
end

--- Average round damage at any AC and mode, for the sweep chart.
function damage.meanForAC(a, s, ac, mode)
  local hit, crit = damage.hitChances(a.bonus, ac, mode, rules.critMin(a))
  return a.attacks * (hit * damage.expectedFrom(s.hitDice, a.mod)
                    + crit * damage.expectedFrom(s.critDice, a.mod))
end

return damage
