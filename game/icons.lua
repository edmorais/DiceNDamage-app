--[[
  icons.lua -- the four tab icons, drawn with shapes rather than loaded.

    calc      a pocket calculator         the Calculator tab
    attack    a sword, point up and right the Attack tab
    damage    an impact burst             the Damage tab
    percent   a percent sign              the Percent tab

  Each is designed in a 24-unit box centred on the origin and scaled to the
  size asked for, so the same drawing serves a 22-unit tab and a 25-unit
  Roll button and stays sharp at any screen density. They are one colour,
  taking whatever ink the control around them uses.

  The Roll buttons carry the icon of the tab their result lands on: the
  Calculator's Roll attack shows the sword because it throws the d20 on the
  Attack tab, and the Attack tab's Damage button shows the burst.
--]]

local lg = love.graphics

local icons = {}

local function calc()
  lg.setLineWidth(2)
  lg.rectangle("line", -8, -11, 16, 22, 2.5, 2.5, 8)
  lg.rectangle("fill", -5, -8, 10, 4.8, 1, 1, 4)
  local k = 2.6
  for _, ky in ipairs({ 0, 3.8, 7.6 }) do
    for _, kx in ipairs({ -4.5, 0, 4.5 }) do
      lg.rectangle("fill", kx - k * 0.5, ky - k * 0.5, k, k, 0.6, 0.6, 3)
    end
  end
end

-- Every piece is convex, so plain polygons fill it correctly.
local function sword()
  lg.push()
  lg.rotate(math.pi / 4)
  lg.polygon("fill", 0, -15, 2.6, -11, 2.6, 5, -2.6, 5, -2.6, -11)
  lg.rectangle("fill", -7, 5, 14, 2.6, 0.8, 0.8, 3)
  lg.rectangle("fill", -1.4, 7.6, 2.8, 4.9)
  lg.circle("fill", 0, 14, 2.2, 16)
  lg.pop()
end

-- An impact burst: eleven spikes of uneven length at slightly uneven angles,
-- so it reads as a hit rather than as a compass star. It is not convex, but
-- it is star-shaped about its centre, so a fan from the centre through its
-- outline covers it exactly once.
local OUTER = { 12, 8, 11, 9.5, 12, 7.5, 10.5, 9, 12, 8.5, 10.2 }
local INNER = { 6.2, 5.6, 6.6, 5.8, 6.2, 5.4, 6.4, 6.0, 5.8, 6.4, 5.6 }
local SKEW = { 0, 6, -4, 5, -3, 4, -6, 2, -2, 5, -4 }        -- degrees
local burstMesh

local function burst()
  if not burstMesh then
    local v = { { 0, 0 } }
    local n = #OUTER
    local rot = math.rad(-75)
    for i = 0, n do
      local k = i % n
      local a = rot + k * 2 * math.pi / n + math.rad(SKEW[k + 1])
      v[#v + 1] = { math.cos(a) * OUTER[k + 1], math.sin(a) * OUTER[k + 1] }
      if i < n then
        local b = rot + (k + 0.5) * 2 * math.pi / n
        v[#v + 1] = { math.cos(b) * INNER[k + 1], math.sin(b) * INNER[k + 1] }
      end
    end
    burstMesh = lg.newMesh(v, "fan", "static")
  end
  lg.draw(burstMesh)
end

local function percent()
  lg.setLineWidth(2.2)
  lg.circle("line", -6.5, -6.5, 3.4, 24)
  lg.circle("line", 6.5, 6.5, 3.4, 24)
  lg.setLineWidth(2.4)
  lg.line(7.5, -10.5, -7.5, 10.5)
end

local DRAW = { calc = calc, attack = sword, damage = burst, percent = percent }

icons.NAMES = { "calc", "attack", "damage", "percent" }

--- Draws icon `name` centred on (cx, cy), `size` units square.
function icons.draw(name, cx, cy, size, c, a)
  local f = DRAW[name]
  if not f or (a or 1) <= 0 then return end
  lg.push()
  lg.translate(cx, cy)
  lg.scale(size / 24)
  lg.setColor(c[1], c[2], c[3], a or 1)
  f()
  lg.pop()
  lg.setLineWidth(1)
end

return icons
