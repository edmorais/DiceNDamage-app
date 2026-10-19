--[[
  ui.lua -- layout, text, shapes, touch targets, widgets and the die renderer.

  A port of UI.pde. Everything is measured in design units: a column 390 wide
  inside a viewport at least 800 tall, scaled to the device's safe area. The
  frame is drawn under one love.graphics.scale(S), so positions, line widths
  and shapes are all in design units.

  Input goes the other way through exactly one division, in ui.toDesign.
  Touches and mouse positions both arrive in window units -- LOVE's
  Event.cpp maps them with normalizedToDPICoords and windowToDPICoords, the
  same units as love.graphics.getWidth() -- so dividing by the layout scale is
  the whole conversion. Multiplying or dividing by a pixel ratio here is what
  made the first Android Dice Roller untappable.

  Text is the one place pixels matter: glyphs are rasterised in pixels while
  everything else is in window units. So fonts are built at device-pixel size
  (units * S * px, where px is pixels per window unit) and drawn with the
  inverse scale, and stay crisp at any density. px is used for nothing else.

  Widgets are immediate mode. Anything touchable registers its rectangle while
  it draws, input is matched against the list the last frame left, and
  nothing holds its own value. Everything acts on release, so a finger that
  starts on a control and drags can still scroll the page. Every (id, arg)
  pair on screen is unique -- two controls sharing one is how the prototype's
  chart chips once started a scrub instead of switching charts.
--]]

local palettes = require("palettes")
local rules = require("rules")
local icons = require("icons")

local lg = love.graphics

local ui = {
  DESIGN_W = 390, DESIGN_H = 800, PAD = 16, COL_W = 358,
  S = 1, px = 1, VW = 390, VH = 800, COLX = 16, TOP = 0,
  hits = {}, clipT = -1e9, clipB = 1e9,
  press = nil,
  LABEL = 12, BODY = 15, NUM = 20, BIG = 24,
}

local mix = palettes.mix

-- ---------------------------------------------------------------- layout

local fontCache = {}

-- The web app's typefaces, so the two read as one design. DejaVu Sans stays
-- as the fallback for every face: it has the ✓, ✎, ⚔ and the rest that the
-- display faces lack.
--   body, medium, bold   Alegreya Sans      text, buttons, names
--   display              IM Fell English SC character names, headings, verdicts
--   num                  Cinzel             totals, the big numbers, die faces
--   mono, monoM          IBM Plex Mono      labels, axes, stepper values
local FACES = {
  body = "AlegreyaSans-Regular.ttf", medium = "AlegreyaSans-Medium.ttf", bold = "AlegreyaSans-Bold.ttf",
  display = "IMFellEnglishSC.ttf", num = "Cinzel.ttf",
  mono = "IBMPlexMono-Regular.ttf", monoM = "IBMPlexMono-Medium.ttf",
}
local FALLBACK = "DejaVuSans.ttf"

--- Scales the column to the safe area, centred. Rebuilds fonts when the
--- scale or the pixel ratio changes.
function ui.computeLayout()
  local sx, sy, sw, sh = 0, 0, lg.getWidth(), lg.getHeight()
  if love.window.getSafeArea then
    local okay, a, b, c, d = pcall(love.window.getSafeArea)
    if okay and type(c) == "number" and c > 0 and d > 0 then sx, sy, sw, sh = a, b, c, d end
  end
  local px = 1
  if lg.getPixelWidth and lg.getWidth() > 0 then px = lg.getPixelWidth() / lg.getWidth() end
  local s = math.min(sw / ui.DESIGN_W, sh / ui.DESIGN_H)
  if s ~= ui.S or px ~= ui.px then fontCache = {} end
  ui.S, ui.px = s, px
  ui.VW, ui.VH = sx / s + sw / s, sy / s + sh / s
  ui.TOP = sy / s
  ui.COLX = sx / s + (sw / s - ui.DESIGN_W) * 0.5 + ui.PAD
end

function ui.toDesign(x, y)
  return x / ui.S, y / ui.S
end

-- ---------------------------------------------------------------- colour

function ui.set(c, a)
  lg.setColor(c[1], c[2], c[3], a or 1)
end

ui.mix = mix

-- ---------------------------------------------------------------- text
-- y is always the top of the line box.

local function load(file, pxSize)
  local okay, made = pcall(lg.newFont, file, pxSize)
  return okay and made or nil
end

local function font(units, face)
  face = face or "body"
  local pxSize = math.max(6, math.floor(units * ui.S * ui.px + 0.5))
  local key = face .. ":" .. pxSize
  local f = fontCache[key]
  if not f then
    local fb = fontCache["fallback:" .. pxSize]
    if not fb then
      fb = load(FALLBACK, pxSize) or lg.newFont(pxSize)
      fb:setFilter("linear", "linear")
      fontCache["fallback:" .. pxSize] = fb
    end
    f = load(FACES[face] or FACES.body, pxSize)
    if f then f:setFallbacks(fb) else f = fb end
    f:setFilter("linear", "linear")
    fontCache[key] = f
  end
  return f, units / pxSize
end
ui.fontFor = font

function ui.th(size, face)
  local f, k = font(size, face)
  return f:getHeight() * k
end

function ui.tw(s, size, face)
  local f, k = font(size, face)
  return f:getWidth(s) * k
end

--- align is "left", "center" or "right"; x is that edge (or the centre).
function ui.txt(s, x, y, size, c, a, align, face)
  a = a or 1
  if a <= 0 then return end
  local f, k = font(size, face)
  local w = f:getWidth(s) * k
  if align == "center" then x = x - w * 0.5 elseif align == "right" then x = x - w end
  ui.set(c, a)
  lg.setFont(f)
  lg.print(s, x, y, 0, k, k)
end

--- Text centred vertically in a box.
function ui.txtIn(s, x, y, h, size, c, a, align, face)
  ui.txt(s, x, y + (h - ui.th(size, face)) * 0.5, size, c, a, align, face)
end

--- Shortens with an ellipsis, a whole character at a time, until it fits.
function ui.fit(s, size, maxW, face)
  if ui.tw(s, size, face) <= maxW then return s end
  local e = "…"
  local cut = s
  while cut ~= "" and ui.tw(cut .. e, size, face) > maxW do cut = rules.dropLast(cut) end
  return cut:gsub("%s+$", "") .. e
end

--- Small capitals in the mono face, spaced out: the labels above controls.
--- LOVE has no letter spacing, so each character is placed by hand.
function ui.caps(s, x, y, size, c, a, align)
  s = s:upper()
  local track = size * 0.12
  local w = ui.tw(s, size, "mono") + track * (math.max(0, rules.length(s) - 1))
  if align == "center" then x = x - w * 0.5 elseif align == "right" then x = x - w end
  for cp in rules.codepoints(s) do
    local ch = rules.encodeCodepoint(cp)
    ui.txt(ch, x, y, size, c, a, "left", "mono")
    x = x + ui.tw(ch, size, "mono") + track
  end
  return w
end

--- Scaled about its own centre, for the total's reveal pop.
function ui.txtPop(s, cx, cy, size, c, k, a, align, face)
  lg.push()
  lg.translate(cx, cy)
  lg.scale(k)
  ui.txt(s, 0, -ui.th(size, face) * 0.5, size, c, a, align or "center", face)
  lg.pop()
end

-- ---------------------------------------------------------------- shapes

local function radius(r, w, h) return math.max(0, math.min(r or 0, w * 0.5, h * 0.5)) end

function ui.box(c, x, y, w, h, r, a)
  a = a or 1
  if a <= 0 or w <= 0 or h <= 0 then return end
  ui.set(c, a)
  local rr = radius(r, w, h)
  lg.rectangle("fill", x, y, w, h, rr, rr, 12)
end

function ui.outline(c, x, y, w, h, r, lw, a)
  ui.set(c, a or 1)
  lg.setLineWidth(lw or 1)
  local rr = radius(r, w, h)
  lg.rectangle("line", x, y, w, h, rr, rr, 12)
  lg.setLineWidth(1)
end

function ui.card(p, x, y, w, h)
  ui.box(p.panel, x, y, w, h, 14)
  ui.outline(p.edge, x, y, w, h, 14, 1, 1)
end

function ui.dashed(x1, y1, x2, y2, dash, gap)
  local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
  if len <= 0 then return end
  local dx, dy = (x2 - x1) / len, (y2 - y1) / len
  local t = 0
  while t < len do
    local e = math.min(len, t + dash)
    lg.line(x1 + dx * t, y1 + dy * t, x1 + dx * e, y1 + dy * e)
    t = t + dash + gap
  end
end

--- Clips drawing to a band of the screen, in design units. The scissor is
--- in window units and ignores transforms, hence the multiplication.
function ui.clip(y, h)
  lg.setScissor(0, math.floor(y * ui.S), lg.getWidth(), math.ceil(h * ui.S))
end

function ui.noClip()
  lg.setScissor()
end

-- ---------------------------------------------------------------- targets

function ui.beginFrame()
  ui.hits = {}
  ui.clipT, ui.clipB = -1e9, 1e9
end

--- Registers a touch target, clipped to the scroll view. Returns it, or nil
--- when it is scrolled out of sight. `shown` is what the control displays --
--- a stepper's value, "on" for the selected chip -- for the tests to read.
function ui.target(id, arg, x, y, w, h)
  local y0, y1 = math.max(y, ui.clipT), math.min(y + h, ui.clipB)
  if y1 <= y0 or w <= 0 then return nil end
  local t = { id = id, arg = arg, x = x, y = y0, w = w, h = y1 - y0, shown = "" }
  ui.hits[#ui.hits + 1] = t
  return t
end

--- Topmost target under a point: later registrations win, so a sheet drawn
--- over the page is found before the page behind it.
function ui.pick(px, py)
  for i = #ui.hits, 1, -1 do
    local t = ui.hits[i]
    if px >= t.x and px <= t.x + t.w and py >= t.y and py <= t.y + t.h then return t end
  end
end

function ui.inside(t, px, py, slop)
  slop = slop or 0
  return t ~= nil and px >= t.x - slop and px <= t.x + t.w + slop
     and py >= t.y - slop and py <= t.y + t.h + slop
end

function ui.isStepper(t) return t.id:sub(1, 2) == "s." end

function ui.isDown(id, arg)
  local p = ui.press
  return p ~= nil and p.hit ~= nil and not p.scrolling and p.hit.id == id and p.hit.arg == arg
end

-- ---------------------------------------------------------------- widgets

--- A small label above a control; returns the y below it.
function ui.label(p, s, x, y)
  ui.caps(s, x, y + 1, 10.5, p.inkDim)
  return y + ui.th(ui.LABEL) + 6
end

--- `- value +`. The ends are separate targets so a hold can repeat one. An
--- optional middle target makes the value itself tappable: that is how a
--- dice group cycles its die size.
function ui.stepper(p, x, y, w, h, id, value, canLo, canHi, midId, midArg)
  local b = h
  ui.box(p.sunken, x, y, w, h, 10)
  ui.outline(p.edge, x, y, w, h, 10, 1, 1)
  if ui.isDown(id, -1) and canLo then ui.box(p.barLow, x, y, b, h, 10) end
  if ui.isDown(id, 1) and canHi then ui.box(p.barLow, x + w - b, y, b, h, 10) end
  ui.txtIn("−", x + b * 0.5, y, h, ui.BIG, canLo and p.accent or p.inkDim, canLo and 1 or 0.35, "center")
  ui.txtIn("+", x + w - b * 0.5, y, h, ui.BIG, canHi and p.accent or p.inkDim, canHi and 1 or 0.35, "center")
  local lo, hi = ui.target(id, -1, x, y, b, h), ui.target(id, 1, x + w - b, y, b, h)
  if lo then lo.shown = value end
  if hi then hi.shown = value end
  if midId then
    if ui.isDown(midId, midArg) then ui.box(p.barLow, x + b, y + 4, w - b * 2, h - 8, 8) end
    ui.target(midId, midArg, x + b, y, w - b * 2, h)
  end
  ui.txtIn(value, x + w * 0.5, y, h, ui.NUM - 2, midId and p.accent or p.ink, 1, "center", "monoM")
end

--- A row of mutually exclusive chips. Each option is a text label, or an
--- icon name when `iconSize` is given.
function ui.chips(p, id, x, y, w, h, opts, active, size, iconSize)
  local gap = 6
  local cw = (w - gap * (#opts - 1)) / #opts
  for i, opt in ipairs(opts) do
    local cx = x + (i - 1) * (cw + gap)
    local on = i == active
    ui.box(on and p.accent or (ui.isDown(id, i) and p.barLow or p.sunken), cx, y, cw, h, 10)
    if not on then ui.outline(p.edge, cx, y, cw, h, 10, 1, 1) end
    local ink = on and p.bg or p.inkDim
    if iconSize then
      icons.draw(opt, cx + cw * 0.5, y + h * 0.5, iconSize, ink, 1)
    else
      ui.txtIn(ui.fit(opt, size, cw - 8, "medium"), cx + cw * 0.5, y, h, size, ink, 1, "center", "medium")
    end
    local t = ui.target(id, i, cx, y, cw, h)
    if t and on then t.shown = "on" end
  end
end

--- A single pill. style is "solid", "outline" or "quiet". An optional icon
--- sits to the left of the label, the pair centred together.
function ui.button(p, id, arg, x, y, w, h, label, size, style, tint, enabled, icon)
  if enabled == nil then enabled = true end
  local down = enabled and ui.isDown(id, arg)
  local a = enabled and 1 or 0.4
  tint = tint or p.accent
  local ink
  if style == "solid" then
    ui.box(down and mix(tint, p.bg, 0.25) or tint, x, y, w, h, 12, enabled and 1 or 0.35)
    ink, a = p.bg, enabled and 1 or 0.8
  elseif style == "outline" then
    if down then ui.box(p.barLow, x, y, w, h, 12) end
    ui.outline(tint, x, y, w, h, 12, 1, a)
    ink = tint
  else
    if down then ui.box(p.sunken, x, y, w, h, 12) end
    ink = p.inkDim
  end
  local is = icon and math.floor(size * 1.05 + 0.5) or 0
  local gapI = icon and size * 0.45 or 0
  local face = style == "quiet" and "medium" or "bold"
  local s = ui.fit(label, size, w - 16 - is - gapI, face)
  local total = is + gapI + ui.tw(s, size, face)
  local left = x + (w - total) * 0.5
  if icon then icons.draw(icon, left + is * 0.5, y + h * 0.5, is, ink, a) end
  ui.txtIn(s, left + is + gapI, y, h, size, ink, a, "left", face)
  if enabled then return ui.target(id, arg, x, y, w, h) end
end

-- ---------------------------------------------------------------- dice

local function regular(n, rot, r, sx, sy)
  local v = {}
  for i = 0, n - 1 do
    local a = rot + i * 2 * math.pi / n
    v[#v + 1] = math.cos(a) * r * (sx or 1)
    v[#v + 1] = math.sin(a) * r * (sy or 1)
  end
  return v
end

--- Outline for a die, centred on the origin. Each size has its own
--- silhouette so a d8 is never mistaken for a d10 at a glance.
function ui.dieShape(sides, r)
  local hp, qp = math.pi / 2, math.pi / 4
  if sides == 4 then return regular(3, -hp, r) end
  if sides == 6 then return regular(4, -qp, r) end
  if sides == 8 then return regular(4, -hp, r, 0.86, 1.04) end
  if sides == 10 then return regular(5, -hp, r, 0.94, 1.06) end
  if sides == 12 then return regular(5, hp, r) end
  if sides == 100 then return regular(6, 0, r) end
  return regular(6, -hp, r)
end

--- One die. hot is nil, "max" or "min"; ring is nil or a colour.
function ui.die(p, cx, cy, size, sides, face, alpha, hot, rot, pop, ring)
  local r = size * 0.5
  local fillC, edgeC, inkC = p.edge, p.inkDim, p.ink
  if hot == "max" then fillC, edgeC = mix(p.edge, p.crit, 0.35), p.crit end
  if hot == "min" then fillC, edgeC, inkC = mix(p.bg, p.fumble, 0.16), p.fumble, p.fumble end

  lg.push()
  lg.translate(cx, cy)
  if rot and rot ~= 0 then lg.rotate(rot) end
  if pop and pop ~= 1 then lg.scale(pop) end
  local shape = ui.dieShape(sides, r)
  ui.set(fillC, alpha)
  lg.polygon("fill", shape)
  lg.setLineJoin("bevel")
  ui.set(edgeC, alpha)
  lg.setLineWidth(size * (hot and 0.070 or 0.045))
  lg.polygon("line", shape)
  ui.set(edgeC, alpha * 0.35)
  lg.setLineWidth(size * 0.028)
  lg.polygon("line", ui.dieShape(sides, r * 0.62))
  lg.setLineWidth(1)
  lg.setLineJoin("miter")
  local fs = size * (#face >= 3 and 0.28 or 0.38)
  ui.txt(face, 0, -ui.th(fs, "num") * 0.52, fs, inkC, alpha, "center", "num")
  lg.pop()

  if ring then
    ui.set(ring, alpha)
    lg.setLineWidth(1.5)
    lg.circle("line", cx, cy, r * 1.24, 48)
    lg.setLineWidth(1)
  end
end

--- The burst behind a crit. k runs 0 to 1.
function ui.burst(p, cx, cy, r, k, spokes)
  local fade = 1 - k
  ui.set(p.crit, fade * 0.9)
  lg.setLineWidth(2)
  for i = 1, spokes do
    local a = i / spokes * 2 * math.pi + k * 0.5
    local i0 = r * (1.05 + k * 0.55)
    local i1 = i0 + r * 0.30 * fade
    lg.line(cx + math.cos(a) * i0, cy + math.sin(a) * i0, cx + math.cos(a) * i1, cy + math.sin(a) * i1)
  end
  ui.set(p.crit, fade * 0.5)
  lg.circle("line", cx, cy, r * (1.0 + k * 0.7), 48)
  lg.setLineWidth(1)
end

local DIE_STEPS = { 190, 158, 132, 110, 92, 76, 62, 50, 42, 34, 28, 22, 18 }

--- Largest die size whose grid fits: size, cols, rows, gap.
function ui.dieGrid(n, areaW, areaH, maxSize)
  local gap = 6
  for i, s in ipairs(DIE_STEPS) do
    if not (s > maxSize and i < #DIE_STEPS) then
      local cols = math.min(n, math.max(1, math.floor((areaW + gap) / (s + gap))))
      local rows = math.ceil(n / cols)
      if rows * (s + gap) - gap <= areaH or i == #DIE_STEPS then return s, cols, rows, gap end
    end
  end
  return 18, n, 1, 6
end

return ui
