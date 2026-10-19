--[[
  Logic tests for rules, damage, rolls and session. Plain LuaJIT, no LOVE:

      luajit test/logic.lua

  A port of the prototype's LogicTests.java. Expected values come from the
  5e rules and hand arithmetic, not from the code under test. The Monte Carlo
  section compares two independent implementations of the same rules -- the
  exact enumeration in damage.lua and whole rounds built from rolls.lua --
  and then proves it could notice a disagreement by checking the same samples
  against a deliberately wrong model.
--]]

-- game/ is found beside this file's folder, wherever it is run from.
local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = dir .. "/../game/?.lua;" .. package.path

local rules   = require("rules")
local damage  = require("damage")
local rolls   = require("rolls")
local session = require("session")

local checks = 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then error(msg, 2) end
end
local function near(a, b, eps) return math.abs(a - b) <= eps end

local function scripted(...)
  local v, i = { ... }, 0
  return function(lo, hi)
    i = i + 1
    local x = v[i]
    if x == nil then error("scripted rng drained at draw " .. i, 2) end
    ok(x >= lo and x <= hi, "scripted value " .. x .. " outside " .. lo .. ".." .. hi)
    return x
  end
end

local function sum(d)
  local s = 0
  for i = 0, d.n do s = s + d[i] end
  return s
end

local N, A, D = rules.NORMAL, rules.ADVANTAGE, rules.DISADVANTAGE

-- ---------------------------------------------------------------- maths

local function faces()
  for _, m in ipairs{ D, N, A } do
    local f, s = damage.faceProbs(m), 0
    for k = 1, 20 do s = s + f[k] end
    ok(near(s, 1, 1e-12), "faces sum, mode " .. m)
  end
  ok(near(damage.faceProbs(A)[20], 39 / 400, 1e-15), "adv P(20) = 1 - (19/20)^2")
  ok(near(damage.faceProbs(D)[1], 39 / 400, 1e-15), "dis P(1) = 1 - (19/20)^2")
  ok(near(damage.faceProbs(A)[1], 1 / 400, 1e-15), "adv P(1) = both dice 1")
end

local function hitSplit()
  local h, c, m = damage.hitChances(5, 15, N, 20)          -- hits on 10..19
  ok(near(h, 0.50, 1e-12) and near(c, 0.05, 1e-12) and near(m, 0.45, 1e-12), "+5 vs 15")
  h, c, m = damage.hitChances(30, 5, N, 20)
  ok(near(m, 0.05, 1e-12) and near(h, 0.90, 1e-12), "natural 1 always misses")
  h, c = damage.hitChances(0, 40, N, 20)
  ok(near(h, 0, 1e-12) and near(c, 0.05, 1e-12), "natural 20 always hits")
  ok(near(select(2, damage.hitChances(0, 40, N, 19)), 0.10, 1e-12), "crit on 19-20")
  ok(near(select(2, damage.hitChances(0, 40, N, 18)), 0.15, 1e-12), "crit on 18-20")
  h, c = damage.hitChances(5, 15, A, 20)
  ok(near(h + c, 1 - 0.45 * 0.45, 1e-12), "advantage any hit")
  ok(near(c, 1 - 0.95 * 0.95, 1e-12), "advantage crit")
  h, c = damage.hitChances(5, 15, D, 20)
  ok(near(h + c, 0.55 * 0.55, 1e-12), "disadvantage any hit")
end

local function sums()
  local g = rules.parseDice("1d8+3d6", 4, 15)
  local d = damage.sumDist(g, 1)
  ok(near(sum(d), 1, 1e-12), "1d8+3d6 mass")
  ok(d.n == 26 and d[3] == 0 and d[4] > 0, "1d8+3d6 spans 4..26")
  local mean = 0
  for i = 0, d.n do mean = mean + i * d[i] end
  ok(near(mean, 4.5 + 3 * 3.5, 1e-10), "1d8+3d6 mean 15")
  ok(damage.sumDist(g, 2).n == 52, "crit doubles every group")
end

local function solve()
  -- Longsword: +7, 1d8+4, two attacks, vs AC 15. Hit on 8..19 (0.60), crit
  -- 0.05. A hit averages 8.5, a crit 13: 0.6*8.5 + 0.05*13 = 5.75 each.
  local a = rules.newAttack(7, "1d8", 4, 2, 1)
  local s = damage.solve(a, 15, N)
  ok(near(sum(s.dist), 1, 1e-12), "round mass")
  ok(near(s.mean, 11.5, 1e-10), "longsword mean 11.5, got " .. s.mean)
  ok(damage.max(s) == 40, "longsword max 40")
  ok(near(damage.exactly(s, 0), 0.35 * 0.35, 1e-12), "both miss")
  ok(near(s.ccdf[0], 1, 1e-12) and damage.atLeast(s, damage.max(s) + 1) == 0, "ccdf ends")
  for i = 1, s.ccdf.n do ok(s.ccdf[i] <= s.ccdf[i - 1] + 1e-15, "ccdf never rises") end
  ok(near(damage.meanForAC(a, s, 15, N), s.mean, 1e-10), "sweep agrees with solve")

  local one = rules.copyAttack(a)
  one.attacks = 1
  local s1 = damage.solve(one, 15, N)
  ok(near(s.sd * s.sd, 2 * s1.sd * s1.sd, 1e-9), "variance adds across attacks")

  -- 1d4 - 5 deals nothing on an ordinary hit; only a crit (2d4 - 5) reaches
  -- 1..3, and only when 2d4 >= 6: 6 of 16. P(damage > 0) = 0.05 * 6/16.
  local z = damage.solve(rules.newAttack(10, "1d4", -5, 1, 1), 10, N)
  ok(near(z.dist[0], 1 - 0.01875, 1e-12), "negative damage clamps at zero")
  ok(damage.max(z) == 3 and near(sum(z.dist), 1, 1e-12), "clamped distribution spans 0..3")
  ok(near(z.mean, 0.05 * (1 * 3 + 2 * 2 + 3 * 1) / 16, 1e-12), "clamped mean by hand")

  local c = rules.newAttack(6, "2d6", 3, 2, 2)
  local sc = damage.solve(c, 15, N)
  for _, m in ipairs{ D, N, A } do
    local prev = math.huge
    for ac = 1, 40 do
      local v = damage.meanForAC(c, sc, ac, m)
      ok(v <= prev + 1e-12, "sweep monotone, mode " .. m .. " ac " .. ac)
      prev = v
    end
  end
  for ac = 1, 40 do
    local d, n, v = damage.meanForAC(c, sc, ac, D), damage.meanForAC(c, sc, ac, N), damage.meanForAC(c, sc, ac, A)
    ok(d <= n + 1e-12 and n <= v + 1e-12, "mode ordering at AC " .. ac)
  end

  local big = rules.newAttack(20, "15d20", 20, 4, 3)
  local t0 = os.clock()
  local sb = damage.solve(big, 10, A)
  local ms = (os.clock() - t0) * 1000
  ok(near(sum(sb.dist), 1, 1e-9), "worst case mass")
  ok(ms < 1500, "worst case solve took " .. ms .. " ms")
  print(string.format("  worst case 4 x 15d20+20, crit 18-20: max %d, solve %.0f ms", damage.max(sb), ms))
end

-- ---------------------------------------------------------------- rolls

local function d20Rolls()
  for _, pair in ipairs{ { 4, 17 }, { 17, 4 } } do
    local r = rolls.d20(scripted(pair[1], pair[2]), 0, A, 20)
    ok(r.natural == 17 and #r.dice == 2 and r.dice[r.keep].kept, "advantage keeps high")
    r = rolls.d20(scripted(pair[1], pair[2]), 0, D, 20)
    ok(r.natural == 4, "disadvantage keeps low")
  end
  local tie = rolls.d20(scripted(11, 11), 0, A, 20)
  local kept = 0
  for _, d in ipairs(tie.dice) do if d.kept then kept = kept + 1 end end
  ok(kept == 1, "a tie keeps exactly one die")

  local c = rolls.d20(scripted(20, 1), 7, A, 20)
  ok(c.crit and not c.fumble and c.total == 27, "crit follows the kept die")
  ok(c.dice[1].max and not c.dice[2].min, "the discarded 1 is not highlighted")
  ok(not rolls.d20(scripted(20, 3), 0, D, 20).crit, "a 20 thrown away is no crit")
  local r19 = rolls.d20(scripted(19), 0, N, 19)
  ok(r19.crit and r19.dice[1].max, "19 crits on 19-20 and is drawn hot")
end

local function attackAndCheck()
  ok(not rolls.attack(scripted(1), 30, N, 20, 1).success, "natural 1 misses AC 1")
  ok(rolls.attack(scripted(20), -5, N, 20, 40).success, "natural 20 hits AC 40")
  ok(rolls.attack(scripted(19), -5, N, 19, 40).success, "an expanded crit hits too")
  local m = rolls.attack(scripted(8), 7, N, 20, 15)
  ok(m.success and m.total == 15, "meets AC exactly: hits")
  ok(m.judged and m.isAttack and m.target == 15, "an attack is judged against the AC it was rolled at")

  local ch = rolls.check(scripted(19), 0, N, 0)
  ok(not ch.crit and not ch.judged and not ch.success, "checks: 19 is no crit, DC 0 is not judged")
  ch = rolls.check(scripted(20), 0, N, 25)
  ok(ch.crit and not ch.success, "a natural 20 does not pass a check by itself")
  ok(rolls.check(scripted(10), 4, N, 14).success, "check meets DC")
end

local function damageRolls()
  local g = rules.parseDice("2d8+1d6", 4, 15)
  local r = rolls.damage(scripted(8, 3, 5), g, 4, false)
  ok(#r.dice == 3 and r.total == 20 and not r.allMax, "damage total")
  ok(r.dice[1].max and r.dice[2].sides == 8 and r.dice[3].sides == 6, "damage dice in order")
  r = rolls.damage(scripted(1, 1, 1, 1, 1, 1), g, 0, true)
  ok(#r.dice == 6 and r.doubled and r.total == 6, "doubled on a crit")
  ok(rolls.damage(scripted(8, 8, 6), g, 0, false).allMax, "every die maxed")
  ok(not rolls.damage(scripted(), {}, 0, false).allMax, "no dice is not all max")
  local pc = rolls.percent(scripted(100))
  ok(pc.percent and pc.total == 100 and pc.dice[1].max and #pc.dice == 1, "d100 top")
  ok(rolls.percent(scripted(1)).dice[1].min, "d100 bottom")
end

-- A round as the table plays it, built only from rolls.attack and
-- rolls.damage -- the dice the app throws.
local function round(rng, a, ac, mode)
  local dealt, total = {}, 0
  for i = 1, a.attacks do
    local r = rolls.attack(rng, a.bonus, mode, rules.critMin(a), ac)
    dealt[i] = 0
    if r.success then dealt[i] = math.max(0, rolls.damage(rng, a.groups, a.mod, r.crit).total) end
    total = total + dealt[i]
  end
  return dealt, total
end

local function rounds()
  local d, t = round(scripted(17, 6, 20, 5, 4), rules.newAttack(7, "1d8", 4, 2, 1), 15, N)
  ok(d[1] == 10 and d[2] == 13 and t == 23, "round 10 + 13 = 23")
  ok(select(2, round(scripted(1, 3), rules.newAttack(7, "1d8", 4, 2, 1), 15, N)) == 0, "misses roll no damage")
  ok(round(scripted(15, 1), rules.newAttack(7, "1d4", -5, 1, 1), 15, N)[1] == 0,
     "a hit for less than zero deals zero")
end

-- ---------------------------------------------------------------- monte carlo

local function tv(p, q)
  local s = 0
  for i = 0, math.max(p.n, q.n) do s = s + math.abs((p[i] or 0) - (q[i] or 0)) end
  return s / 2
end

-- Chance alone gives E|p_hat - p| = sqrt(2/pi) sd per value, so expected TV is
-- about 0.8 of half the summed standard errors; the bound is 1.5 times that
-- half-sum, nearly twice what chance produces.
local function noise(p, n)
  local s = 0
  for i = 0, p.n do s = s + math.sqrt(p[i] * (1 - p[i]) / n) end
  return 1.5 * s / 2
end

local function monteCarlo()
  local n = 400000
  local cases = {
    { "longsword vs 15",             rules.newAttack(7, "1d8", 4, 2, 1),          15, N },
    { "greatsword adv, crit 19-20",  rules.newAttack(8, "2d6", 5, 2, 2),          17, A },
    { "sneak attack disadv.",        rules.newAttack(7, "1d8+3d6", 4, 1, 1),      14, D },
    { "negative bonus, clamps",      rules.newAttack(3, "1d4", -3, 3, 3),         12, N },
    { "four attacks, three groups",  rules.newAttack(9, "1d10+2d6+1d4", 5, 4, 2), 18, N },
  }
  math.randomseed(20260927)
  local rng = function(lo, hi) return math.random(lo, hi) end
  for _, c in ipairs(cases) do
    local a, ac, mode = c[2], c[3], c[4]
    local s = damage.solve(a, ac, mode)
    local emp = { n = s.dist.n }
    for i = 0, emp.n do emp[i] = 0 end
    for _ = 1, n do
      local _, t = round(rng, a, ac, mode)
      if t < 0 or t > emp.n then error("simulated total " .. t .. " outside the exact support") end
      emp[t] = emp[t] + 1
    end
    local mean = 0
    for i = 0, emp.n do emp[i] = emp[i] / n; mean = mean + i * emp[i] end
    local d, bound = tv(emp, s.dist), noise(s.dist, n)
    local se = s.sd / math.sqrt(n)
    print(string.format("  %-28s mean %7.3f exact %7.3f (%.1f se)   TV %.4f, chance bound %.4f",
                        c[1], mean, s.mean, math.abs(mean - s.mean) / se, d, bound))
    ok(math.abs(mean - s.mean) < 5 * se, c[1] .. ": simulated mean disagrees with the exact mean")
    ok(d < bound, c[1] .. ": simulated distribution disagrees with the exact one")
    local wrong = damage.solve(a, ac + 1, mode)
    local dw = tv(emp, wrong.dist)
    print(string.format("  %-28s against AC %d instead: TV %.4f, %.1fx the bound", "", ac + 1, dw, dw / bound))
    ok(dw > bound, c[1] .. ": the test cannot tell AC " .. ac .. " from AC " .. (ac + 1))
  end
end

-- ---------------------------------------------------------------- session

local function joinedEq(a, b) return session.joined(a) == session.joined(b) end

local function varied()
  local s = session.fresh()
  s.attack = rules.newAttack(-3, "2d10+1d4+1d6+1d8+1d12", 33, 3, 3)
  s.ac, s.rollMode, s.targetHp = 27, D, 44
  s.checkMod, s.checkDc, s.doubleDice = -2, 31, true
  s.tab, s.attackSub, s.palIdx, s.chart, s.showCcdf = 4, 2, 6, 2, false
  s.presets[#s.presets + 1] = { name = "Espada longa (Ação) +1", attack = rules.newAttack(9, "1d8+2d6", 6, 2, 2) }
  s.active = 4
  return s
end

local function sessionRoundTrip()
  local a = varied()
  local b = session.fresh()
  ok(session.decode(session.encode(a), b), "round trip refused its own output")
  ok(joinedEq(a, b), "round trip changed something:\n" .. session.joined(a) .. "\n---\n" .. session.joined(b))
  ok(b.presets[4].name == "Espada longa (Ação) +1", "accented name survives")
  ok(b.active == 4 and session.edited(b), "active preset survives, and it reads as edited")

  local e = session.fresh()
  e.presets, e.active = {}, 0
  local e2 = session.fresh()
  session.decode(session.encode(e), e2)
  ok(#e2.presets == 0 and e2.active == 0, "an emptied list does not come back seeded")
end

-- The exact text the Processing prototype writes for its default state: the
-- port must read it, and write it back identically.
local PROTOTYPE = {
  "v=1", "bonus=7", "dice=1d8", "mod=4", "attacks=2", "crit=0", "ac=15", "mode=1", "hp=20",
  "checkmod=3", "checkdc=0", "double=0", "tab=0", "sub=0", "pal=0", "chart=0", "ccdf=1", "active=0",
  "preset=Longsword|7|1d8|4|2|0", "preset=Rapier and Sneak Attack|7|1d8+3d6|4|1|0",
  "preset=Champion greatsword|8|2d6|5|2|1",
}

local function prototypeFormat()
  ok(session.joined(session.fresh()) == table.concat(PROTOTYPE, "\n"),
     "the port's default session is not byte-identical to the prototype's:\n" .. session.joined(session.fresh()))
  local s = session.fresh()
  s.tab, s.palIdx = 3, 2
  ok(session.decode({ "v=1", "tab=0", "pal=5", "mode=2", "crit=2", "active=-1", "chart=1", "sub=1" }, s),
     "prototype keys refused")
  ok(s.tab == 1 and s.palIdx == 6 and s.rollMode == A and s.attack.crit == 3 and s.chart == 2
     and s.attackSub == 2, "0-based file values became the right 1-based ones")
  ok(s.active == 0, "active=-1 means no preset")
end

local function sessionHostile()
  for _, bad in ipairs{ {}, { "garbage" }, { "v=2", "bonus=3" }, { "v" } } do
    local s = session.fresh()
    local before = session.joined(s)
    ok(not session.decode(bad, s), "accepted " .. table.concat(bad, ","))
    ok(session.joined(s) == before, "a refused file changed the state")
  end

  local s = session.fresh()
  session.decode({ "v=1", "bonus=999", "ac=-4", "pal=77", "attacks=x", "tab=9", "hp=3.5" }, s)
  ok(s.attack.bonus == rules.BONUS_MAX and s.ac == rules.AC_MIN and s.palIdx == 6, "clamped")
  ok(s.attack.attacks == 2 and s.tab == 4 and s.targetHp == 20, "a garbled number keeps its default")

  s = session.fresh()
  session.decode({
    "v=1",
    "preset=Good|5|1d8|3|1|0",
    "preset=Too many fields|5|1d8|3|1|0|9",
    "preset=Bad die|5|1d7|3|1|0",
    "preset=Bad bonus|99|1d8|3|1|0",
    "preset=Bad crit|5|1d8|3|1|3",
    "preset=|5|1d8|3|1|0",
    "preset=Over cap|5|15d6+1d8|3|1|0",
    "preset=Also good|6|2d6+1d4|2|2|1",
    "active=1",
  }, s)
  ok(#s.presets == 2 and s.presets[2].name == "Also good", "bad presets dropped individually")
  ok(s.active == 2, "active index kept when valid")

  local many = { "v=1" }
  for i = 0, 11 do many[#many + 1] = "preset=P" .. i .. "|1|1d6|0|1|0" end
  many[#many + 1] = "active=11"
  s = session.fresh()
  session.decode(many, s)
  ok(#s.presets == rules.MAX_PRESETS and s.presets[8].name == "P7", "capped at eight")
  ok(s.active == 0, "an active index past the list is dropped")

  local d = session.fresh()
  d.presets[1].name = "Pipe|and=equals\nnewline"
  local d2 = session.fresh()
  session.decode(session.encode(d), d2)
  ok(#d2.presets == 3 and d2.presets[1].name == "Pipeandequalsnewline", "delimiters stripped: " .. d2.presets[1].name)
  ok(d2.presets[2].name == "Rapier and Sneak Attack", "the next preset is unharmed")

  -- Windows line endings and a missing final newline, as a hand edit leaves them.
  local w = session.fresh()
  ok(session.decode(session.lines("v=1\r\nac=22\r\nbonus=4"), w) and w.ac == 22 and w.attack.bonus == 4,
     "CRLF lines read")
end

local function legacy()
  local s = session.fresh()
  ok(session.decode({
    "v=1", "bonus=6", "dice=2d6+1d4", "mod=3", "attacks=2", "crit=0", "ac=17",
    "judge=0", "mode=2", "hp=18", "pool=8d6+2d8", "poolmod=-7", "pooldouble=1",
    "preset=Old|5|1d8+1d6+1d4+1d10|2|1|0", "active=0",
  }, s), "an earlier prototype's session is refused")
  ok(s.attack.bonus == 6 and rules.encodeDice(s.attack.groups) == "2d6+1d4" and s.attack.mod == 3,
     "the attack is what the old session saved, not its pool")
  ok(s.ac == 17 and not s.doubleDice, "the old pool's crit toggle is not carried over")
  ok(#s.presets == 1 and #s.presets[1].attack.groups == 4, "the old preset loads")

  local five = session.parsePreset("Five|5|1d4+1d6+1d8+1d10+1d12|45|1|0")
  ok(five and #five.attack.groups == 5 and five.attack.mod == 45, "five groups, +45")
  ok(#session.parsePreset("Six|5|1d4+1d6+1d8+1d10+1d12+1d20|4|1|0").attack.groups == 5, "a sixth group is dropped")
  ok(session.parsePreset("Too far|5|1d8|51|1|0") == nil, "a damage bonus past 50 is refused")
end

local function names()
  ok(rules.sanitizeName("  Great   axe  ") == "Great axe", "whitespace collapses and trims")
  ok(rules.length(rules.sanitizeName("abcdefghijklmnopqrstuvwxyz")) == rules.NAME_MAX, "cut to 24")
  local dagger = "\240\159\151\161\239\184\143 Dagger"          -- dagger emoji, variation selector
  local cut = rules.sanitizeName(dagger .. dagger .. dagger .. dagger)
  ok(rules.length(cut) <= rules.NAME_MAX, "counted in characters")
  local valid = 0
  for _ in rules.codepoints(cut) do valid = valid + 1 end
  ok(valid == rules.length(cut) and #table.concat((function() local t = {} for cp in rules.codepoints(cut) do t[#t + 1] = rules.encodeCodepoint(cp) end return t end)()) == #cut,
     "the cut never splits a character")
  ok(rules.sanitizeName("\0\7") == "", "control characters removed")
  ok(rules.sanitizeName("Axe\237\160\189") == "Axe", "an encoded surrogate is dropped")
  ok(rules.sanitizeName("\255Axe\192\128") == "Axe", "invalid and overlong bytes are dropped")
  ok(rules.sanitizeName("A\194\160B") == "A\194\160B", "a no-break space is kept, as Java kept it")
  ok(rules.dropLast("Ação") == "Açã" and rules.dropLast("") == "", "backspace removes a whole character")
end

local function attackModel()
  local s = session.fresh()
  ok(not session.edited(s), "a freshly loaded preset is not edited")
  s.attack.bonus = s.attack.bonus + 1
  ok(session.edited(s), "a change marks it edited")
  s.presets[s.active].attack = rules.copyAttack(s.attack)
  ok(not session.edited(s), "update clears it")
  s.attack.groups[1].d = 10
  ok(session.edited(s) and s.presets[1].attack.groups[1].d == 8, "copies are deep")

  local a = { bonus = 5, groups = rules.parseDice("8d6+8d8", 4, 30), mod = 3, attacks = 1, crit = 1 }
  rules.clampAttack(a)
  ok(rules.diceCount(a) == rules.MAX_DICE, "clampAttack trims to fifteen dice, got " .. rules.diceCount(a))
  ok(rules.MAX_DICE * 2 <= 30, "a crit can never overflow the tray")
  ok(#rules.parseDice("2d8+1d7+0d6+3d6", 4, 15) == 2, "impossible groups skipped")
  ok(#rules.parseDice("15d6+1d8", 4, 15) == 0, "an over-cap spec is refused whole")
  ok(rules.nextSize(20) == 4 and rules.nextSize(4) == 6, "die sizes cycle")
end

faces(); hitSplit(); sums(); solve()
d20Rolls(); attackAndCheck(); damageRolls(); rounds()
print("  monte carlo, 400,000 rounds per case:")
monteCarlo()
sessionRoundTrip(); prototypeFormat(); sessionHostile(); legacy(); names(); attackModel()
print("logic: " .. checks .. " checks passed")
