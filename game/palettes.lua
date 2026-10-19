--[[
  palettes.lua -- eleven colour schemes: the six shared by the Damage
  Calculator, the Dice Roller and the Processing prototype, hex for hex, and
  the web app's five.

  Every drawing call reads from the active scheme. Roles, not names:

    bg       screen behind the cards       ink      primary text
    panel    card fill                     inkDim   secondary text
    edge     card border, die faces        grid     hairlines, chart grid
    accent   buttons, active tab, mean     accent2  cumulative curve, HP line
    barLow   pressed fills, low bars       barHigh  high bars, hit ribbon
    miss     the miss slice                crit     a crit, a maxed die

  Two are derived rather than authored:

    fumble   a natural 1: miss lifted toward inkDim until it reads on a card
    sunken   fill for controls that sit inside a card

  Colours are rounded to whole 8-bit steps after mixing, as Processing's were,
  so a derived colour is the same byte in both builds.
--]]

local function hex(s)
  return { tonumber(s:sub(1, 2), 16) / 255,
           tonumber(s:sub(3, 4), 16) / 255,
           tonumber(s:sub(5, 6), 16) / 255 }
end

local function round8(x) return math.floor(x * 255 + 0.5) / 255 end

local function mix(a, b, t)
  return { round8(a[1] + (b[1] - a[1]) * t),
           round8(a[2] + (b[2] - a[2]) * t),
           round8(a[3] + (b[3] - a[3]) * t) }
end

local KEYS = { "bg", "panel", "edge", "ink", "inkDim", "grid",
               "accent", "accent2", "barLow", "barHigh", "miss", "crit" }

local function scheme(t)
  local p = { name = t[1] }
  for i, k in ipairs(KEYS) do p[k] = hex(t[i + 1]) end
  p.fumble = mix(p.miss, p.inkDim, 0.75)
  p.sunken = mix(p.panel, p.edge, 0.55)
  return p
end

local palettes = {
  scheme{ "Dragon's Hoard",
    "12100E", "1C1815", "2E2620", "F2E7D5", "A2917A", "2B2420",
    "E0A526", "C6482B", "6E4A21", "F2C14E", "4A3A30", "FF7A45" },
  scheme{ "Spellbook",
    "E7DABB", "F6EEDC", "D3C09A", "33291D", "7A6A52", "DFD0AE",
    "8A4B0F", "1F5C4E", "D9C098", "7A4A1E", "BBAF98", "A02C2C" },
  scheme{ "Arcane Neon",
    "080A1B", "101433", "22265A", "E8E9FF", "8A8FCB", "1B2050",
    "4CC9F0", "F72585", "3A0CA3", "4CC9F0", "262B5E", "F72585" },
  scheme{ "Necrotic Bloom",
    "0B1310", "12201A", "1E3529", "DDF7E3", "7FA98D", "172A21",
    "9EF01A", "38B000", "14532D", "9EF01A", "233B2E", "D9ED92" },
  scheme{ "Frostbite",
    "071019", "0E1B29", "1B3550", "E4F1FB", "86A5BF", "14293D",
    "63C7FF", "FFB703", "14496B", "8ECAE6", "1E3040", "FFB703" },
  scheme{ "Ink & Bone",
    "0D0D0D", "161616", "2A2A2A", "EDEDED", "9A9A9A", "232323",
    "FFFFFF", "B0B0B0", "3C3C3C", "E6E6E6", "2A2A2A", "FFFFFF" },
  -- The web app's five, in its order, so a party file's scheme index means
  -- the same colours on both.
  scheme{ "Infernal",
    "140A09", "1F0F0D", "3A1A15", "F5E3D7", "B39282", "2E1511",
    "FF5A1F", "E8B04A", "6B1A10", "FF8A3D", "47231C", "FFD166" },
  scheme{ "Feywild",
    "120E1F", "1C1630", "32294F", "F1EAFF", "ADA1CF", "251E40",
    "F28AD2", "7EE8B5", "4B2C78", "C79BFF", "2E2648", "FFE27A" },
  scheme{ "Underdark",
    "07080C", "0F1117", "1F2430", "E2E6EE", "8E97AA", "171B24",
    "3EE6C8", "B57BFF", "16424A", "5CF2D6", "222733", "FFC857" },
  scheme{ "Abyssal Tide",
    "04141A", "0A1F27", "15363F", "E0F4F2", "83ABAB", "0F2A32",
    "2EC4B6", "F4D58D", "0E4D55", "7DE2D1", "1A3138", "FF6B6B" },
  scheme{ "Celestial",
    "EEF0F4", "FBFBFD", "D3D8E2", "1E2433", "5A647C", "E1E5EC",
    "8F6510", "2F6FB5", "C9D3E6", "3B5BA0", "D9DDE5", "B83A0E" },
}

palettes.mix = mix
palettes.KEYS = KEYS

return palettes
