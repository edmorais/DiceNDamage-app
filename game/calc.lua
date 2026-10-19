--[[
  calc.lua -- the Damage Calculator, and the preset bar the tabs share.

  The column scrolls between the tabs and a fixed bottom bar holding Roll
  attack. That button does not roll here: it switches to the Attack tab and
  throws the d20 there, with the bonus, roll mode and AC this tab shows --
  the same values, not copies of them.

  A port of CalcTab.pde.
--]]

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local damage = require("damage")
local session = require("session")

local lg = love.graphics
local calc = {}

calc.CHARTS = { "Distribution", "Damage vs AC" }
calc.MODES = { "Disadvantage", "Normal", "Advantage" }
local SWEEP_LO, SWEEP_HI = 5, 30

local function solveSig()
  local st = app.st
  local a = st.attack
  return a.bonus .. "|" .. rules.encodeDice(a.groups) .. "|" .. a.mod .. "|" .. a.attacks
      .. "|" .. a.crit .. "|" .. st.ac .. "|" .. st.rollMode
end

function calc.ensureSolved()
  local s = solveSig()
  if s ~= app.solSig then
    app.sol = damage.solve(app.st.attack, app.st.ac, app.st.rollMode)
    app.solSig = s
  end
end

function calc.pct(v)
  if v <= 0 then return "0%" end
  if v >= 1 then return "100%" end
  if v < 0.001 then return "<0.1%" end
  if v > 0.999 then return ">99.9%" end
  return string.format("%.1f%%", v * 100)
end

local pct = calc.pct
local function dec1(v) return string.format("%.1f", v) end

local function stroke(c, a, w)
  ui.set(c, a)
  lg.setLineWidth(w)
end

-- ---------------------------------------------------------------- presets

--- Shared by the Calculator, the Attack tab and the Damage tab. Returns its
--- height.
function calc.drawPresetBar(p, x, y, w)
  local st = app.st
  local h = 56
  local down = ui.isDown("presets", 0)
  ui.box(down and p.sunken or p.panel, x, y, w, h, 14)
  ui.outline(p.edge, x, y, w, h, 14, 1, 1)

  local bw, bh = 86, 32
  local bx, by = x + w - bw - 12, y + (h - bh) * 0.5
  ui.outline(p.accent, bx, by, bw, bh, 16, 1, 1)
  ui.txtIn("Presets", bx + bw * 0.5, by, bh, ui.BODY, p.accent, 1, "center", "bold")

  local loaded = st.presets[st.active]
  local name = loaded and loaded.name or "Unsaved attack"
  local maxW = bx - (x + 14) - 12
  local edited = session.edited(st)
  local tag = edited and "  edited" or ""
  local face = loaded and "bold" or "medium"
  local shown = ui.fit(name, 17, maxW - ui.tw(tag, ui.LABEL + 1), face)
  ui.txt(shown, x + 14, y + 8, 17, loaded and p.ink or p.inkDim, 1, "left", face)
  if edited then ui.txt(tag, x + 14 + ui.tw(shown, 17, face), y + 11, ui.LABEL + 1, p.accent2, 1) end
  ui.txt(ui.fit(rules.summary(st.attack), ui.LABEL + 1, maxW), x + 14, y + 31, ui.LABEL + 1, p.inkDim)

  ui.target("presets", 0, x, y, w, h)
  return h
end

-- ---------------------------------------------------------------- hero

--- What the d20 has to show to hit: a natural 1 always misses and the crit
--- range always hits, so the answer is somewhere from 2 to the crit range.
function calc.needed(a, ac)
  return math.max(2, math.min(ac - a.bonus, rules.critMin(a)))
end

local function neededText(a, ac)
  local n = calc.needed(a, ac)
  if n <= 2 then return "hits on anything but a 1" end
  if n >= 20 then return "only a 20 hits" end
  if n >= rules.critMin(a) then return "only a crit hits (" .. n .. "+)" end
  return "needs " .. n .. "+ on the d20"
end
calc.neededText = neededText

--- The two numbers that matter, side by side, then how each attack splits
--- between crit, hit and miss.
local HERO_H = 168

local function drawHero(p, x, y, w, h)
  local st, sol = app.st, app.sol
  local a = st.attack
  ui.card(p, x, y, w, h)
  local half = (w - 28) * 0.5
  local lx, rx = x + 14, x + 14 + half + 14
  local any = sol.pHit + sol.pCrit

  ui.caps("Chance to hit", lx, y + 14, 10.5, p.inkDim)
  ui.txt(pct(any), lx - 1, y + 30, 40, p.accent, 1, "left", "num")
  ui.txt(neededText(a, st.ac), lx, y + 82, ui.LABEL + 1, p.inkDim)

  ui.set(p.edge, 1)
  lg.setLineWidth(1)
  lg.line(rx - 14, y + 16, rx - 14, y + 98)
  ui.caps("Average damage", rx, y + 14, 10.5, p.inkDim)
  ui.txt(dec1(sol.mean), rx - 1, y + 30, 40, p.ink, 1, "left", "num")
  local per = a.attacks > 1 and ("per round, " .. a.attacks .. " attacks") or "per round"
  ui.txt(per, rx, y + 82, ui.LABEL + 1, p.inkDim)

  -- Each attack: crit, then hit, then miss, in one bar.
  local bx, bw, by, bh = x + 14, w - 28, y + 112, 8
  ui.box(p.miss, bx, by, bw, bh, 4)
  ui.box(p.barHigh, bx, by, bw * any, bh, 4)
  ui.box(p.crit, bx, by, bw * sol.pCrit, bh, 4)
  local ly = by + bh + 8
  ui.txt("Crit " .. pct(sol.pCrit), bx, ly, ui.LABEL + 1, p.crit)
  ui.txt("Miss " .. pct(sol.pMiss), bx + bw, ly, ui.LABEL + 1, p.inkDim, 1, "right")
  local mid
  if a.attacks > 1 then
    mid = "At least one hits " .. pct(1 - sol.pMiss ^ a.attacks)
  else
    mid = "±" .. dec1(sol.sd) .. ", max " .. damage.max(sol)
  end
  ui.txt(mid, bx + bw * 0.5, ly, ui.LABEL + 1, p.ink, 1, "center")
end

-- ---------------------------------------------------------------- charts

local function readout()
  local c, sol = app.calc, app.sol
  if c.scrub >= 0 and app.st.chart == 1 then
    return "Exactly " .. c.scrub .. ": " .. pct(damage.exactly(sol, c.scrub)) .. "     "
        .. c.scrub .. " or more: " .. pct(damage.atLeast(sol, c.scrub))
  end
  return "Drag across the chart to read the odds of any total"
end

function calc.scrubAt(dx)
  local c, sol = app.calc, app.sol
  local u = (dx - c.plotX) / c.plotW
  if app.st.chart == 1 then
    local n = damage.max(sol) + 1
    c.scrub = rules.clamp(math.floor(u * n), 0, damage.max(sol))
  else
    c.scrub = rules.clamp(math.floor(SWEEP_LO + u * (SWEEP_HI - SWEEP_LO) + 0.5), SWEEP_LO, SWEEP_HI)
  end
end

-- Labels inside a plot are placed, not just drawn: each one tries a row near
-- the top and drops to the next if it would overlap one already there, and
-- sits on a panel-coloured backing so the curve behind never hides it.
local placed = {}

local function plotTag(p, s, ax, px, py, pw, c, solid, a)
  local w, h = ui.tw(s, 10) + 10, 16
  for row = 0, 4 do
    local y = py + 1 + row * (h + 2)
    local x
    if solid then x = math.max(px, math.min(px + pw - w, ax - w * 0.5))
    else x = (ax + 3 + w <= px + pw) and ax + 3 or ax - 3 - w end
    local clash = false
    for _, r in ipairs(placed) do
      if x < r[3] and x + w > r[1] and y < r[4] and y + h > r[2] then clash = true break end
    end
    if not (clash and row < 4) then
      if solid then
        ui.box(c, x, y, w, h, 5, a)
        ui.txtIn(s, x + w * 0.5, y, h, 10, p.bg, a, "center")
      else
        ui.box(p.panel, x, y, w, h, 5, 0.88 * a)
        ui.txtIn(s, x + w * 0.5, y, h, 10, c, a, "center")
      end
      placed[#placed + 1] = { x - 2, y, x + w + 2, y + h }
      return
    end
  end
end

local function niceStep(raw)
  local e = 1
  while e < 100000 do
    for _, k in ipairs({ 1, 2, 5 }) do
      if k * e >= raw then return k * e end
    end
    e = e * 10
  end
  return 100000
end

--- Fills a polygon that may be concave, as the ragged top of a cut column is.
local function fillShape(pts)
  local okay, tris = pcall(love.math.triangulate, pts)
  if okay and tris then
    for _, t in ipairs(tris) do lg.polygon("fill", t) end
  end
end

local function drawDistribution(p, px, py, pw, ph)
  local st, sol, scrub = app.st, app.sol, app.calc.scrub
  local d = sol.dist
  local n = d.n + 1                                     -- values 0 .. n-1

  local rest = 0
  for v = 1, n - 1 do rest = math.max(rest, d[v]) end
  local clipZero = rest > 0 and d[0] > rest * 2.2
  local top = clipZero and rest * 1.15 or math.max(d[0], rest) * 1.08
  if top <= 0 then top = 1 end

  -- Grid and the probability axis.
  for g = 0, 4 do
    local gy = py + ph - g * ph / 4
    stroke(p.grid, 1, 1)
    lg.line(px, gy, px + pw, gy)
    local label = pct(top * g / 4):gsub("%.0%%", "%%")
    ui.txt(label, px - 6, gy - ui.th(10, "mono") * 0.5, 9.5, p.inkDim, 1, "right", "mono")
  end

  -- One column per ~2.2 units, each showing the peak of the values it covers.
  local cols = math.max(1, math.min(n, math.floor(pw / 2.2)))
  for c = 0, cols - 1 do
    local lo = math.floor(c * n / cols)
    local hi = math.max(lo, math.floor((c + 1) * n / cols) - 1)
    local peak = 0
    for v = lo, hi do peak = math.max(peak, d[v]) end
    if peak > 0 then
      local x0, x1 = px + lo / n * pw, px + (hi + 1) / n * pw
      local bw = math.max(0.8, (x1 - x0) - ((x1 - x0) > 3 and 1 or 0))
      -- The gradient starts partway up from barLow: on the dark schemes
      -- barLow is close to the panel, and below-threshold bars are dimmed on
      -- top of it.
      local colr = ui.mix(ui.mix(p.barLow, p.barHigh, 0.35), p.barHigh, cols > 1 and c / (cols - 1) or 1)
      local zeroCol = lo == 0 and hi == 0
      if zeroCol then colr = ui.mix(p.miss, p.inkDim, 0.35) end
      local scrubbed = scrub >= lo and scrub <= hi and st.chart == 1
      local bh = math.min(1, peak / top) * ph
      ui.box(scrubbed and p.ink or colr, x0, py + ph - bh, bw, bh, 0, 1)

      if lo == 0 and clipZero then
        -- The miss column dwarfs the rest: cut it with a ragged top and say so.
        ui.set(p.panel, 1)
        local zx, zw = x0, bw
        local pts = { zx - 1, py - 1, zx + zw + 1, py - 1, zx + zw + 1, py + 4 }
        for i = 4, 0, -1 do
          pts[#pts + 1] = zx + zw * i / 4
          pts[#pts + 1] = py + (i % 2 == 0 and 7 or 2)
        end
        fillShape(pts)
      end
    end
  end

  -- Damage axis.
  local step = niceStep((n - 1) / 6)
  for v = 0, n - 1, step do
    local vx = px + (v + 0.5) / n * pw
    ui.txt(tostring(v), vx, py + ph + 6, 9.5, p.inkDim, 1, "center", "mono")
  end

  -- Mean.
  local mx = px + (sol.mean + 0.5) / n * pw
  stroke(p.accent, 1, 1.5)
  ui.dashed(mx, py, mx, py + ph, 5, 4)

  -- Cumulative curve on its own 0-100% scale, labelled in its own colour at
  -- the right so it is never read against the bars' axis on the left.
  if st.showCcdf then
    local pts = {}
    for v = 0, n - 1 do
      pts[#pts + 1] = px + (v + 0.5) / n * pw
      pts[#pts + 1] = py + ph - sol.ccdf[v] * ph
    end
    stroke(p.accent2, 0.95, 2)
    lg.setLineJoin("bevel")
    if #pts >= 4 then lg.line(pts) end
    lg.setLineJoin("miter")
    ui.txt("100%", px + pw + 6, py - ui.th(10) * 0.5, 10, p.accent2, 1)
    ui.txt("50%", px + pw + 6, py + ph * 0.5 - ui.th(10) * 0.5, 10, p.accent2, 1)
    ui.txt("0%", px + pw + 6, py + ph - ui.th(10) * 0.5, 10, p.accent2, 1)
  end
  lg.setLineWidth(1)

  placed = {}
  plotTag(p, "avg " .. dec1(sol.mean), mx, px, py, pw, p.accent, false, 1)
  if clipZero then plotTag(p, "no damage " .. pct(d[0]), px + (0.5 / n) * pw, px, py, pw, p.inkDim, false, 1) end
end

local function acX(ac, px, pw)
  return px + (ac - SWEEP_LO) / (SWEEP_HI - SWEEP_LO) * pw
end

local function modeColors(p) return { p.inkDim, p.barHigh, p.accent2 } end

local function drawSweep(p, px, py, pw, ph)
  local st, sol, scrub = app.st, app.sol, app.calc.scrub
  local curves, top = { {}, {}, {} }, 0
  for m = 1, 3 do
    for ac = SWEEP_LO, SWEEP_HI do
      curves[m][ac] = damage.meanForAC(st.attack, sol, ac, m)
      top = math.max(top, curves[m][ac])
    end
  end
  top = top > 0 and top * 1.12 or 1

  for g = 0, 4 do
    local gy = py + ph - g * ph / 4
    stroke(p.grid, 1, 1)
    lg.line(px, gy, px + pw, gy)
    ui.txt(dec1(top * g / 4), px - 6, gy - ui.th(10, "mono") * 0.5, 9.5, p.inkDim, 1, "right", "mono")
  end

  for ac = SWEEP_LO, SWEEP_HI do
    if ac % 5 == 0 then
      local ax = acX(ac, px, pw)
      stroke(p.grid, 1, 1)
      lg.line(ax, py, ax, py + ph)
      ui.txt(ac == SWEEP_LO and ("AC " .. ac) or tostring(ac), ax, py + ph + 6, 9.5, p.inkDim, 1, "center", "mono")
    end
  end

  local here = rules.clamp(st.ac, SWEEP_LO, SWEEP_HI)
  stroke(p.accent, 1, 1.5)
  ui.dashed(acX(here, px, pw), py, acX(here, px, pw), py + ph, 6, 5)

  local cols = modeColors(p)
  lg.setLineJoin("bevel")
  for m = 1, 3 do
    local pts = {}
    for ac = SWEEP_LO, SWEEP_HI do
      pts[#pts + 1] = acX(ac, px, pw)
      pts[#pts + 1] = py + ph - (curves[m][ac] / top) * ph
    end
    stroke(cols[m], 1, m == st.rollMode and 3 or 1.5)
    lg.line(pts)

    local vy = py + ph - (curves[m][here] / top) * ph
    ui.set(cols[m], 1)
    lg.circle("fill", acX(here, px, pw), vy, (m == st.rollMode and 9 or 6) * 0.5, 24)
  end
  lg.setLineJoin("miter")

  if scrub >= 0 then
    stroke(p.ink, 0.8, 1)
    lg.line(acX(scrub, px, pw), py, acX(scrub, px, pw), py + ph)
  end
  lg.setLineWidth(1)
end

--- On the sweep the readout line is the legend: each mode's average at the
--- current AC, or at the AC under the finger while scrubbing. A legend
--- inside the plot would sit on the curves at some AC whatever corner it
--- chose.
local function drawSweepLegend(p, x, y, w, ac)
  local st, sol = app.st, app.sol
  local cols = modeColors(p)
  local names = { "Disadv.", "Normal", "Adv." }
  local head = "AC " .. ac
  ui.txt(head, x, y, ui.LABEL, app.calc.scrub >= 0 and p.ink or p.inkDim)
  local cx = x + ui.tw(head, ui.LABEL) + 14
  local lh = ui.th(ui.LABEL)
  for m = 1, 3 do
    local s = names[m] .. " " .. dec1(damage.meanForAC(st.attack, sol, ac, m))
    ui.box(cols[m], cx, y + lh * 0.5 - 1.5, 12, 3, 1.5)
    ui.txt(s, cx + 16, y, ui.LABEL, m == st.rollMode and p.ink or p.inkDim)
    cx = cx + 16 + ui.tw(s, ui.LABEL) + 14
  end
end

local function drawChartCard(p, x, y, w, h)
  local st, c = app.st, app.calc
  ui.card(p, x, y, w, h)
  ui.chips(p, "chart", x + 12, y + 12, 222, 30, calc.CHARTS, st.chart, ui.LABEL)

  if st.chart == 1 then
    local bw = 104
    local bx = x + w - 12 - bw
    local on = st.showCcdf
    local down = ui.isDown("ccdf", 0)
    ui.box(down and p.barLow or (on and ui.mix(p.panel, p.accent2, 0.18) or p.sunken), bx, y + 12, bw, 30, 10)
    ui.outline(on and p.accent2 or p.edge, bx, y + 12, bw, 30, 10, 1, 1)
    ui.txtIn((on and "✓ " or "") .. "Cumulative", bx + bw * 0.5, y + 12, 30, ui.LABEL,
             on and p.accent2 or p.inkDim, 1, "center")
    local t = ui.target("ccdf", 0, bx, y + 12, bw, 30)
    if t and on then t.shown = "on" end
  end

  if st.chart == 1 then
    ui.txt(ui.fit(readout(), ui.LABEL, w - 28), x + 14, y + 52, ui.LABEL, c.scrub >= 0 and p.ink or p.inkDim)
  else
    drawSweepLegend(p, x + 14, y + 52, w - 28, c.scrub >= 0 and c.scrub or st.ac)
  end

  local px, py, pw, ph = x + 44, y + 80, w - 44 - 44, h - 80 - 30
  c.plotX, c.plotW = px, pw
  if st.chart == 1 then drawDistribution(p, px, py, pw, ph) else drawSweep(p, px, py, pw, ph) end
  local t = ui.target("plot", 0, px - 8, py, pw + 16, ph)
  if t then t.shown = st.chart == 1 and "distribution" or "sweep" end
end

-- ---------------------------------------------------------------- controls

--- A section heading in the display face, with an optional note at the right.
function calc.heading(p, s, x, y, w, note)
  ui.txt(s, x, y, 21, p.ink, 1, "left", "display")
  if note then ui.txt(note, x + w, y + 6, ui.LABEL + 1, p.inkDim, 1, "right") end
  return y + ui.th(21, "display") + 8
end

local function drawSituation(p, x, y, w)
  local st = app.st
  y = calc.heading(p, "The situation", x, y, w)

  local hw = (w - 10) * 0.5
  ui.label(p, "Enemy AC", x, y)
  y = ui.label(p, "On the d20", x + hw + 10, y)
  ui.stepper(p, x, y, hw, 46, "s.ac", tostring(st.ac), st.ac > rules.AC_MIN, st.ac < rules.AC_MAX)
  -- Next to the AC, what the die has to show against it.
  local bx = x + hw + 10
  ui.set(p.edge, 1)
  lg.setLineWidth(1)
  for _, seg in ipairs({ { bx, y, bx + hw, y }, { bx, y + 46, bx + hw, y + 46 }, { bx, y, bx, y + 46 }, { bx + hw, y, bx + hw, y + 46 } }) do
    ui.dashed(seg[1], seg[2], seg[3], seg[4], 4, 3)
  end
  local need = calc.needed(st.attack, st.ac)
  local txt = need <= 2 and "2 or more" or (need >= 20 and "20 only" or (need .. " or more"))
  ui.txtIn(txt, bx + hw * 0.5, y, 46, ui.NUM - 2, p.ink, 1, "center", "monoM")
  y = y + 46 + 14

  y = ui.label(p, "Roll mode", x, y)
  ui.chips(p, "mode", x, y, w, 42, calc.MODES, st.rollMode, ui.LABEL)
  return y + 42
end

--- Dice group rows, shared with the Damage tab. Tap a group's label to cycle
--- its die size; the ends change how many; the cross removes it.
function calc.drawGroupRows(p, x, y, w, groups, maxGroups, room, title)
  ui.caps(title, x, y + 8, 10.5, p.inkDim)
  local canAdd = #groups < maxGroups and room >= 1
  ui.button(p, "gadd", 0, x + w - 96, y, 96, 28, "+ Add dice", ui.LABEL,
            canAdd and "outline" or "quiet", p.accent, canAdd)
  y = y + 34

  local removable = #groups > 1
  for i, g in ipairs(groups) do
    ui.stepper(p, x, y, removable and w - 44 or w, 42, "s.g" .. i, g.n .. "d" .. g.d,
               g.n > 1, room > 0, "gdie", i)
    if removable then ui.button(p, "gdel", i, x + w - 38, y, 38, 42, "×", ui.NUM, "quiet", p.inkDim, true) end
    y = y + 42 + 5
  end
  return y - 5
end

local function drawAttackEditor(p, x, y, w)
  local a = app.st.attack
  y = calc.heading(p, "Your attack", x, y, w, "saved with presets")

  local hw = (w - 10) * 0.5
  ui.label(p, "Attack bonus", x, y)
  y = ui.label(p, "Attacks per round", x + hw + 10, y)
  ui.stepper(p, x, y, hw, 46, "s.bonus", rules.signed(a.bonus), a.bonus > rules.BONUS_MIN, a.bonus < rules.BONUS_MAX)
  ui.stepper(p, x + hw + 10, y, hw, 46, "s.attacks", tostring(a.attacks),
             a.attacks > rules.ATTACKS_MIN, a.attacks < rules.ATTACKS_MAX)
  y = y + 46 + 14

  y = calc.drawGroupRows(p, x, y, w, a.groups, rules.MAX_GROUPS, rules.room(a), "Damage dice")
  y = y + 8

  ui.label(p, "Damage bonus", x, y)
  y = ui.label(p, "Crit range", x + hw + 10, y)
  ui.stepper(p, x, y, hw, 46, "s.mod", rules.signed(a.mod), a.mod > rules.MOD_MIN, a.mod < rules.MOD_MAX)
  ui.chips(p, "crit", x + hw + 10, y, hw, 46, rules.CRIT_LABELS, a.crit, ui.LABEL)
  return y + 46
end

-- ---------------------------------------------------------------- frame

function calc.draw(p, top)
  calc.ensureSolved()
  local c = app.calc

  local rollH = 58
  local rollY = ui.VH - 14 - rollH
  c.viewT, c.viewB = top, rollY - 12

  local viewH = c.viewB - c.viewT
  c.scroll = math.max(0, math.min(c.scroll, math.max(0, c.contentH - viewH)))

  ui.clip(c.viewT, viewH)
  ui.clipT, ui.clipB = c.viewT, c.viewB

  local x, w = ui.COLX, ui.COL_W
  local y0 = c.viewT - c.scroll
  local y = y0
  y = y + calc.drawPresetBar(p, x, y, w) + 10
  drawHero(p, x, y, w, HERO_H)       y = y + HERO_H + 10
  drawChartCard(p, x, y, w, 282)     y = y + 282 + 20
  y = drawSituation(p, x, y, w) + 22
  y = drawAttackEditor(p, x, y, w) + 18
  c.contentH = y - y0

  ui.noClip()
  ui.clipT, ui.clipB = -1e9, 1e9

  -- A thin thumb at the edge when there is more column than screen.
  if c.contentH > viewH + 1 then
    local th = math.max(30, viewH * viewH / c.contentH)
    local ty = c.viewT + (viewH - th) * (c.scroll / (c.contentH - viewH))
    ui.box(p.inkDim, x + w + 6, ty, 3, th, 1.5, 0.45)
  end

  ui.button(p, "roll", 0, x, rollY, w, rollH, "Roll attack", ui.BIG, "solid", p.accent, true, "attack")
end

return calc
