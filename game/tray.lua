--[[
  tray.lua -- the roll animation and the pieces every dice tray is made of.

  Dice tumble for about four tenths of a second showing nonsense faces, then
  settle one after another with a short bounce; the stagger shrinks as the
  handful grows. The result appears once the last die is down. A tap on the
  tray, or on Roll while it reads Skip, jumps straight to the result.

  A port of Tray.pde.
--]]

local app = require("app")
local ui = require("ui")
local rules = require("rules")

local tray = {}

-- ---------------------------------------------------------------- animation

local Anim = {}
Anim.__index = Anim

function tray.newAnim(n)
  local a = setmetatable({ t = 0, settle = {}, spin = {}, revealAt = 0 }, Anim)
  local stagger = math.min(0.07, 0.6 / math.max(1, n - 1))
  for i = 1, n do
    a.settle[i] = 0.42 + (i - 1) * stagger + app.random(0.06)
    a.spin[i] = app.random(10)
    a.revealAt = math.max(a.revealAt, a.settle[i])
  end
  a.revealAt = a.revealAt + 0.24
  return a
end

function Anim:rolling() return self.t < self.revealAt end
function Anim:revealed() return self.t >= self.revealAt end
function Anim:since() return self.t - self.revealAt end
function Anim:skip() self.t = math.max(self.t, self.revealAt) end

-- ---------------------------------------------------------------- views

--- One tab's last roll, its animation, and its recent totals.
local RollView = {}
RollView.__index = RollView

function tray.newView()
  return setmetatable({ d20 = nil, d20Text = "", d20Anim = nil,
                        dmg = nil, dmgText = "", dmgAnim = nil,
                        recent = {}, d20Logged = false, dmgLogged = false }, RollView)
end

function RollView:setD20(r, text)
  self.d20, self.d20Text = r, text
  self.d20Anim = tray.newAnim(#r.dice)
  self.d20Logged = false
  self.dmg, self.dmgAnim = nil, nil
end

function RollView:setDamage(r)
  self.dmg = r
  self.dmgText = tray.describe(r)
  self.dmgAnim = tray.newAnim(#r.dice)
  self.dmgLogged = false
end

function RollView:rolling()
  return (self.d20Anim ~= nil and self.d20Anim:rolling())
      or (self.dmgAnim ~= nil and self.dmgAnim:rolling())
end

function RollView:skip()
  if self.d20Anim then self.d20Anim:skip() end
  if self.dmgAnim then self.dmgAnim:skip() end
end

function RollView:log(s)
  table.insert(self.recent, 1, s)
  while #self.recent > 6 do table.remove(self.recent) end
end

function RollView:advance(dt)
  if self.d20Anim then
    self.d20Anim.t = self.d20Anim.t + dt
    if not self.d20Logged and self.d20Anim:revealed() then
      self.d20Logged = true
      self:log(tostring(self.d20.total))
    end
  end
  if self.dmgAnim then
    self.dmgAnim.t = self.dmgAnim.t + dt
    if not self.dmgLogged and self.dmgAnim:revealed() then
      self.dmgLogged = true
      self:log(self.dmg.percent and (self.dmg.total .. "%") or tostring(math.max(0, self.dmg.total)))
    end
  end
end

function tray.resetViews()
  app.views = { attack = tray.newView(), check = tray.newView(),
                damage = tray.newView(), percent = tray.newView() }
end

function tray.allViews()
  local v = app.views
  return { v.attack, v.check, v.damage, v.percent }
end

function tray.currentView()
  local st = app.st
  if st.tab == app.ATTACK then return st.attackSub == 1 and app.views.attack or app.views.check end
  if st.tab == app.DAMAGE then return app.views.damage end
  return app.views.percent
end

-- ---------------------------------------------------------------- dice sets

--- Lays out and draws a handful of dice in an area, animated by `a`.
--- d20Mode: a kept die gets a ring when there are two, the discarded one
--- fades and shrinks, and a crit bursts on the die itself. Otherwise a crit
--- -- every die on its top face -- gets one burst around the whole handful,
--- because per die the bursts overlap into noise and the moment belongs to
--- the set.
function tray.drawDice(p, dice, a, ax, ay, aw, ah, maxSize, d20Mode, crit, fumble)
  local n = #dice
  if n == 0 or ah < 10 then return end
  local size, cols, rows, gap = ui.dieGrid(n, aw, ah, maxSize)
  local gridW, gridH = cols * (size + gap) - gap, rows * (size + gap) - gap
  local gy = ay + (ah - gridH) * 0.5
  local revealed = a:revealed()

  if not d20Mode and crit and revealed and n > 1 then
    ui.burst(p, ax + aw * 0.5, gy + gridH * 0.5, math.max(gridW, gridH) * 0.42,
             math.min(1, a:since() / 0.6), 20)
  end

  for i, d in ipairs(dice) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local inRow = math.min(cols, n - row * cols)
    local rowX = ax + (aw - (inRow * (size + gap) - gap)) * 0.5
    local cx = rowX + col * (size + gap) + size * 0.5
    local cy = gy + row * (size + gap) + size * 0.5

    local settle, spin = a.settle[i], a.spin[i]
    local face = tostring(d.value)
    local rot, pop, jx, jy, alpha = 0, 1, 0, 0, 1

    if a.t < settle then
      face = tostring(1 + math.floor((a.t * 26 + spin) % d.sides))
      rot = math.sin(a.t * 17 + spin) * 0.32
      jy = math.sin(a.t * 23 + spin * 2) * size * 0.06
    else
      local u = math.min(1, (a.t - settle) / 0.24)
      pop = 1 + 0.26 * math.sin(u * math.pi) * (1 - u)
    end

    if not d.kept and revealed then
      local u = math.min(1, a:since() / 0.28)
      alpha = 1 - 0.74 * u
      pop = pop * (1 - 0.18 * u)
    end

    local hot = nil
    if revealed and d.kept then hot = d.max and "max" or (d.min and "min" or nil) end

    if revealed and fumble and d.kept and d.min then
      local u = a:since()
      if u < 0.55 then jx = math.sin(u * 48) * size * 0.07 * (1 - u / 0.55) end
    end

    if revealed and crit and d.kept and d.max and (d20Mode or n == 1) then
      ui.burst(p, cx + jx, cy + jy, size * 0.5, math.min(1, a:since() / 0.6), 12)
    end

    local ring = nil
    if d20Mode and n > 1 and d.kept and revealed then
      ring = crit and p.crit or (fumble and p.fumble or p.barHigh)
    end

    ui.die(p, cx + jx, cy + jy, size, d.sides, face, alpha, hot, rot, pop, ring)
  end
end

--- "2d8 + 1d6 + 4" rebuilt from the dice actually thrown.
function tray.describe(r)
  if r.percent then return "d100" end
  local g = {}
  for _, d in ipairs(r.dice) do
    local last = g[#g]
    if last and last.d == d.sides then last.n = last.n + 1
    else g[#g + 1] = { n = 1, d = d.sides } end
  end
  return rules.diceText(g, false) .. rules.modText(r.mod)
end

--- Banner and total, popping in once the dice are down.
function tray.drawVerdict(p, x, w, bannerY, totalCy, banner, bannerC, total, totalC, a, totalSize)
  local u = math.min(1, a:since() / 0.20)
  local k = 0.55 + 0.45 * (1 - (1 - u) ^ 3) + 0.12 * math.sin(u * math.pi)
  if banner then
    -- Cinzel: inscriptional capitals, with lining figures for "Hits AC 15".
    local bw, bh = ui.tw(banner, 14, "num") + 28, 24
    ui.box(ui.mix(p.panel, bannerC, 0.20), x + (w - bw) * 0.5, bannerY - 1, bw, bh, 12)
    ui.txtIn(banner, x + w * 0.5, bannerY - 1, bh, 14, bannerC, 1, "center", "num")
  end
  ui.txtPop(total, x + w * 0.5, totalCy, totalSize, totalC, k, 1, "center", "num")
end

function tray.drawRecent(p, x, y, w, list)
  if #list == 0 then return end
  ui.caps("Recent", x + 14, y + 2, 9, p.inkDim, 0.75)
  local rx = x + w - 14
  for i, s in ipairs(list) do
    local pw = ui.tw(s, 10, "mono") + 12
    if rx - pw < x + 66 then break end
    rx = rx - pw
    ui.box(p.sunken, rx, y, pw, 16, 8)
    ui.txtIn(s, rx + pw * 0.5, y, 16, 10, i == 1 and p.ink or p.inkDim, 1, "center", "mono")
    rx = rx - 5
  end
end

--- An empty tray still shows what is loaded: a ghost of the die a tap on
--- Roll will throw.
function tray.drawGhost(p, x, w, ay, ah, sides, hint)
  local ghost = math.max(0, math.min(130, ah - ui.th(ui.BODY) - 40))
  local blockH = ghost + (ghost > 30 and 18 or 0) + ui.th(ui.BODY)
  local top = ay + (ah - blockH) * 0.5
  if ghost > 30 then ui.die(p, x + w * 0.5, top + ghost * 0.5, ghost, sides, "", 0.30, nil, 0, 1, nil) end
  ui.txt(hint, x + w * 0.5, top + blockH - ui.th(ui.BODY), ui.BODY, p.inkDim, 1, "center")
end

return tray
