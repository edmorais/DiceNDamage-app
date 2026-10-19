--[[
  damagetab.lua -- the attack's damage, and the d100.

  The Damage tab rolls the attack's own damage dice and damage bonus: the
  groups here are the Calculator's groups, so a d6 added on either tab is on
  both, and a preset loaded here changes the Calculator too. Double the dice
  is this tab's crit toggle; the Attack tab's Damage button sets it from the
  d20 it follows.

  Percent throws one d100 and takes no settings at all.

  A port of DamageTab.pde.
--]]

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local tray = require("tray")
local calc = require("calc")

local damagetab = {}

local function drawDiceTray(p, x, y, w, h, v, percent)
  local st = app.st
  ui.card(p, x, y, w, h)
  ui.target("tray", 0, x, y, w, h)

  -- The expression describes the roll on screen, so it comes from the roll
  -- once there is one: edit the dice afterwards and the old result still
  -- reads as what it was. Before any roll it shows what Roll will throw.
  local expr
  if percent then expr = "d100"
  elseif v.dmg then expr = v.dmgText
  else expr = rules.diceText(st.attack.groups, st.doubleDice) .. rules.modText(st.attack.mod) end
  ui.txt(expr, x + w * 0.5, y + 12, ui.LABEL + 1, p.inkDim, 1, "center", "mono")

  local footerH, totalH, bannerH = 22, 60, 26
  local areaY = y + 12 + ui.th(ui.LABEL) + 8
  local areaH = (y + h - footerH - totalH - bannerH) - areaY - 4

  if not v.dmg then
    local sides = percent and 100 or st.attack.groups[1].d
    local count = percent and 1 or rules.diceCount(st.attack) * (st.doubleDice and 2 or 1)
    local hint
    if count > 1 then hint = "Tap Roll damage to throw the dice"
    elseif percent then hint = "Tap Roll to throw the die"
    else hint = "Tap Roll damage to throw the die" end
    tray.drawGhost(p, x, w, areaY, y + h - footerH - areaY - 8, sides, hint)
  else
    local r = v.dmg
    local top = percent and r.dice[1].max or r.allMax
    local bottom = percent and r.dice[1].min
    tray.drawDice(p, r.dice, v.dmgAnim, x + 12, areaY, w - 24, areaH, 190, false, top, bottom)
    if v.dmgAnim:revealed() then
      local banner, bc = nil, p.ink
      if percent and top then banner, bc = "MAXIMUM", p.crit
      elseif percent and bottom then banner, bc = "MINIMUM", p.fumble
      elseif not percent and r.allMax then banner, bc = "MAXIMUM DAMAGE", p.crit
      elseif not percent and r.doubled then banner, bc = "Critical damage", p.accent2 end
      local tint = top and p.crit or (bottom and p.fumble or p.ink)
      -- Damage never goes below zero, as in the Calculator's maths.
      local total = percent and (r.total .. "%") or tostring(math.max(0, r.total))
      tray.drawVerdict(p, x, w, y + h - footerH - totalH - bannerH + 2, y + h - footerH - totalH * 0.5,
                       banner, bc, total, tint, v.dmgAnim, 46)
    end
  end
  tray.drawRecent(p, x, y + h - footerH + 3, w, v.recent)
end

function damagetab.draw(p, top)
  local st = app.st
  local x, w, y = ui.COLX, ui.COL_W, top
  y = y + calc.drawPresetBar(p, x, y, w) + 10

  local rollH = 58
  local rollY = ui.VH - 14 - rollH
  local a = st.attack
  local n = #a.groups
  local ctrlH = 34 + n * 42 + (n - 1) * 5 + 8 + (ui.th(ui.LABEL) + 6) + 46
  local ctrlY = rollY - 12 - ctrlH
  local trayH = math.max(150, math.min(470, ctrlY - 10 - y))
  y = y + math.max(0, (ctrlY - 10 - y) - trayH) * 0.5
  drawDiceTray(p, x, y, w, trayH, app.views.damage, false)
  ctrlY = math.max(ctrlY, y + trayH + 10)

  -- The same ids as the Calculator's rows: they are the same dice.
  local cy = calc.drawGroupRows(p, x, ctrlY, w, a.groups, rules.MAX_GROUPS, rules.room(a), "Damage dice")
  cy = cy + 8
  local hw = (w - 10) * 0.5
  ui.label(p, "Damage bonus", x, cy)
  cy = ui.label(p, "On a crit", x + hw + 10, cy)
  ui.stepper(p, x, cy, hw, 46, "s.mod", rules.signed(a.mod), a.mod > rules.MOD_MIN, a.mod < rules.MOD_MAX)
  local t = ui.button(p, "double", 0, x + hw + 10, cy, hw, 46, "Double the dice", ui.BODY,
                      st.doubleDice and "solid" or "outline", p.crit, true)
  if t and st.doubleDice then t.shown = "on" end

  -- Roll damage, and beside it a new attack: back to the Attack tab and a
  -- fresh d20, so a round goes attack, damage, attack, damage on two buttons.
  local busy = app.views.damage:rolling()
  local gap = 10
  local lw = (w - gap) * 0.58
  ui.button(p, "roll", 0, x, rollY, lw, rollH, busy and "Skip" or "Roll damage", ui.BIG - 2, "solid",
            busy and p.inkDim or p.accent, true, "damage")
  ui.button(p, "rollatk", 0, x + lw + gap, rollY, w - lw - gap, rollH, "New attack", ui.BODY + 2, "outline",
            p.accent, not busy, "attack")
end

function damagetab.drawPercent(p, top)
  local x, w, y = ui.COLX, ui.COL_W, top
  local rollH = 58
  local rollY = ui.VH - 14 - rollH
  local ctrlY = rollY - 12
  local trayH = math.max(150, math.min(470, ctrlY - 10 - y))
  y = y + math.max(0, (ctrlY - 10 - y) - trayH) * 0.5
  drawDiceTray(p, x, y, w, trayH, app.views.percent, true)

  local busy = app.views.percent:rolling()
  ui.button(p, "roll", 0, x, rollY, w, rollH, busy and "Skip" or "Roll", ui.BIG, "solid",
            busy and p.inkDim or p.accent, true, "percent")
end

return damagetab
