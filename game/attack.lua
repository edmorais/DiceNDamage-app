--[[
  attack.lua -- one swing at a time, or an ability check.

  Attack roll: the attack's bonus against the enemy AC, in the roll mode the
  Calculator shows. They are the Calculator's values, not copies: change one
  here and it has changed there. Damage switches to the Damage tab and rolls
  the attack's dice there, doubled when this d20 was a crit.

  Ability check: its own modifier and DC, kept apart from the attack so a Dex
  check never edits the longsword. In 5e a check has no crits, so the 20 and
  the 1 are called natural, not critical, and success is total >= DC.

  A port of AttackTab.pde.
--]]

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local tray = require("tray")
local calc = require("calc")

local lg = love.graphics
local attack = {}

local SUBS = { "Attack roll", "Ability check" }

--- What Roll attack or Roll check will throw, as a line of text.
function attack.d20Expr(isAttack)
  local st = app.st
  local head
  if st.rollMode == rules.ADVANTAGE then head = "2d20 keep high"
  elseif st.rollMode == rules.DISADVANTAGE then head = "2d20 keep low"
  else head = "d20" end
  local expr = head .. rules.modText(isAttack and st.attack.bonus or st.checkMod)
  if isAttack then expr = expr .. "  vs AC " .. st.ac end
  if not isAttack and st.checkDc > 0 then expr = expr .. "  vs DC " .. st.checkDc end
  return expr
end

function attack.verdict(r)
  if r.isAttack then
    if r.crit then return "CRITICAL HIT" end
    if r.fumble then return "CRITICAL FAIL" end
    if r.judged then return (r.success and "Hits AC " or "Misses AC ") .. r.target end
    return nil
  end
  if r.crit then return "NATURAL 20" end
  if r.fumble then return "NATURAL 1" end
  if r.judged then return (r.success and "Passes DC " or "Fails DC ") .. r.target end
  return nil
end

local function verdictColor(p, r)
  if r.crit then return p.crit end
  if r.fumble then return p.fumble end
  return r.success and p.ink or p.inkDim
end

--- A lighter control than the main tabs, so the hierarchy reads at a glance.
local function drawSubSwitch(p, x, y, w, h)
  local hw = w / #SUBS
  ui.set(p.edge, 1)
  lg.setLineWidth(1)
  lg.line(x, y + h - 0.5, x + w, y + h - 0.5)
  for i, name in ipairs(SUBS) do
    local on = app.st.attackSub == i
    local sx = x + (i - 1) * hw
    if ui.isDown("sub", i) then ui.box(p.sunken, sx, y, hw, h, 8) end
    ui.txtIn(name, sx + hw * 0.5, y, h - 3, ui.BODY + 2, on and p.ink or p.inkDim, 1, "center", on and "bold" or "medium")
    if on then ui.box(p.accent, sx + hw * 0.5 - 44, y + h - 3, 88, 3, 1.5) end
    local t = ui.target("sub", i, sx, y, hw, h)
    if t and on then t.shown = "on" end
  end
end

local function drawD20Tray(p, x, y, w, h, v, isAttack)
  ui.card(p, x, y, w, h)
  ui.target("tray", 0, x, y, w, h)

  -- Once there is a roll, the header describes it rather than the settings,
  -- so changing the AC afterwards cannot relabel a result already on screen.
  local expr = v.d20 and v.d20Text or attack.d20Expr(isAttack)
  ui.txt(expr, x + w * 0.5, y + 12, ui.LABEL + 1, p.inkDim, 1, "center", "mono")

  local footerH, totalH, bannerH = 22, 58, 26
  local areaY = y + 12 + ui.th(ui.LABEL) + 8
  local areaH = (y + h - footerH - totalH - bannerH) - areaY - 4

  if not v.d20 then
    tray.drawGhost(p, x, w, areaY, y + h - footerH - areaY - 8, 20,
                   isAttack and "Tap Roll attack to throw the d20" or "Tap Roll check to throw the d20")
  else
    local r = v.d20
    tray.drawDice(p, r.dice, v.d20Anim, x + 12, areaY, w - 24, areaH, 140, true, r.crit, r.fumble)
    if v.d20Anim:revealed() then
      local tint = r.crit and p.crit or (r.fumble and p.fumble or p.ink)
      tray.drawVerdict(p, x, w, y + h - footerH - totalH - bannerH + 2, y + h - footerH - totalH * 0.5,
                       attack.verdict(r), verdictColor(p, r), tostring(r.total), tint, v.d20Anim, 42)
    end
  end

  tray.drawRecent(p, x, y + h - footerH + 3, w, v.recent)
end

function attack.draw(p, top)
  local st = app.st
  local x, w, y = ui.COLX, ui.COL_W, top
  drawSubSwitch(p, x, y, w, 32)
  y = y + 32 + 8

  local rollH = 58
  local rollY = ui.VH - 14 - rollH
  local ctrlH = (ui.th(ui.LABEL) + 6) + 42 + 14 + (ui.th(ui.LABEL) + 6) + 46
  local isAttack = st.attackSub == 1

  if isAttack then y = y + calc.drawPresetBar(p, x, y, w) + 10 end

  local ctrlY = rollY - 12 - ctrlH
  local trayH = math.max(150, math.min(470, ctrlY - 10 - y))
  y = y + math.max(0, (ctrlY - 10 - y) - trayH) * 0.5
  drawD20Tray(p, x, y, w, trayH, isAttack and app.views.attack or app.views.check, isAttack)
  ctrlY = math.max(ctrlY, y + trayH + 10)

  local cy = ui.label(p, "Roll mode", x, ctrlY)
  ui.chips(p, "mode", x, cy, w, 42, calc.MODES, st.rollMode, ui.LABEL)
  cy = cy + 42 + 14

  local hw = (w - 10) * 0.5
  if isAttack then
    ui.label(p, "Attack bonus", x, cy)
    cy = ui.label(p, "Target AC", x + hw + 10, cy)
    ui.stepper(p, x, cy, hw, 46, "s.bonus", rules.signed(st.attack.bonus),
               st.attack.bonus > rules.BONUS_MIN, st.attack.bonus < rules.BONUS_MAX)
    ui.stepper(p, x + hw + 10, cy, hw, 46, "s.ac", tostring(st.ac), st.ac > rules.AC_MIN, st.ac < rules.AC_MAX)

    local v = app.views.attack
    local busy = v:rolling()
    local crit = v.d20 ~= nil and v.d20.crit and v.d20Anim:revealed()
    local gap = 10
    local lw = (w - gap) * 0.58
    ui.button(p, "roll", 0, x, rollY, lw, rollH, busy and "Skip" or "Roll attack", ui.BIG - 2, "solid",
              busy and p.inkDim or p.accent, true, "attack")
    ui.button(p, "rolldmg", 0, x + lw + gap, rollY, w - lw - gap, rollH,
              crit and "Crit damage" or "Damage", ui.BODY + 2, crit and "solid" or "outline",
              crit and p.crit or p.accent, not busy, "damage")
  else
    ui.label(p, "Modifier", x, cy)
    cy = ui.label(p, "Target DC", x + hw + 10, cy)
    ui.stepper(p, x, cy, hw, 46, "s.checkmod", rules.signed(st.checkMod),
               st.checkMod > rules.CHECK_MOD_MIN, st.checkMod < rules.CHECK_MOD_MAX)
    ui.stepper(p, x + hw + 10, cy, hw, 46, "s.checkdc", st.checkDc == 0 and "Off" or tostring(st.checkDc),
               st.checkDc > 0, st.checkDc < rules.DC_MAX)
    local busy = app.views.check:rolling()
    ui.button(p, "roll", 0, x, rollY, w, rollH, busy and "Skip" or "Roll check", ui.BIG, "solid",
              busy and p.inkDim or p.accent, true, "attack")
  end
end

return attack
