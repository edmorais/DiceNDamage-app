--[[
  sheet.lua -- save, load, rename, update and delete attack presets.

  Opened from the preset bar on the Calculator, the Attack tab and the Damage
  tab. A preset stores the attack only; loading one never touches the
  situation. Loaded on any of the three, it is loaded on all of them: there is
  one working attack.

    tap a row        load it and close
    pencil           rename it
    cross            delete it -- the cross becomes Delete, tap again
    Save as new      name the working attack and add it
    Update <name>    overwrite the loaded preset with your edits

  Eight is the limit: enough for a character's whole kit, few enough that the
  sheet never scrolls.

  While a name is being typed the sheet moves to the top of the screen, out
  of the way of the on-screen keyboard that would otherwise cover the field.
  Typed text arrives as UTF-8 from love.textinput and is kept and cut by
  whole characters, never by bytes.

  A port of PresetSheet.pde. Preset indexes count from 1; `editing` is false,
  "new", or the index of the preset being renamed.
--]]

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local session = require("session")

local sheet = {}

local function S() return app.sheet end

--- Turns the on-screen keyboard on while a name is being typed, and off
--- again after. On a desktop this only switches text input events.
local function setEditing(v)
  S().editing = v
  if love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, v ~= false)
  end
end

function sheet.open()
  local s = S()
  s.open, s.confirmDelete = true, 0
  if s.editing then setEditing(false) end
end

function sheet.close()
  local s = S()
  s.open, s.confirmDelete = false, 0
  if s.editing then setEditing(false) end
end

function sheet.isEditing() return S().open and S().editing ~= false end

local function suggestName()
  local i = #app.st.presets + 1
  while true do
    local name = "Attack " .. i
    local used = false
    for _, p in ipairs(app.st.presets) do if p.name == name then used = true end end
    if not used then return name end
    i = i + 1
  end
end

--- Appends typed text, a whole character at a time, up to the name limit.
function sheet.type(text)
  local s = S()
  if not sheet.isEditing() or type(text) ~= "string" then return end
  if s.nameFresh then s.nameBuf, s.nameFresh = "", false end
  local n = rules.length(s.nameBuf)
  local out = { s.nameBuf }
  for cp in rules.codepoints(text) do
    if n >= rules.NAME_MAX then break end
    if cp >= 32 and cp ~= 127 then
      out[#out + 1] = rules.encodeCodepoint(cp)
      n = n + 1
    end
  end
  s.nameBuf = table.concat(out)
end

function sheet.backspace()
  local s = S()
  if not sheet.isEditing() then return end
  if s.nameFresh then s.nameBuf, s.nameFresh = "", false return end
  s.nameBuf = rules.dropLast(s.nameBuf)
end

function sheet.action(id, arg)
  local s, st = S(), app.st
  if id == "backdrop" or id == "pclose" then
    sheet.close()
  elseif s.editing and (id == "pload" or id == "prename" or id == "pdel" or id == "psave" or id == "pupdate") then
    return                                     -- finish or cancel the name first
  elseif id == "pload" then
    local pr = st.presets[arg]
    if pr then
      st.attack = rules.copyAttack(pr.attack)
      st.active = arg
      sheet.close()
      app.say("Loaded " .. pr.name)
    end
  elseif id == "prename" then
    local pr = st.presets[arg]
    if pr then
      s.nameBuf, s.nameFresh = pr.name, true
      setEditing(arg)
    end
  elseif id == "pdel" then
    if not st.presets[arg] then return end
    if s.confirmDelete ~= arg then
      s.confirmDelete = arg
      return
    end
    table.remove(st.presets, arg)
    if st.active == arg then st.active = 0
    elseif st.active > arg then st.active = st.active - 1 end
    s.confirmDelete = 0
  elseif id == "psave" then
    if #st.presets < rules.MAX_PRESETS then
      s.nameBuf, s.nameFresh = suggestName(), true
      setEditing("new")
    end
  elseif id == "pupdate" then
    local pr = st.presets[st.active]
    if pr then
      pr.attack = rules.copyAttack(st.attack)
      app.say("Updated " .. pr.name)
    end
  elseif id == "pcommit" then
    if not s.editing then return end
    local name = rules.sanitizeName(s.nameBuf)
    if name == "" then
      name = s.editing == "new" and suggestName() or (st.presets[s.editing] or {}).name or suggestName()
    end
    if s.editing == "new" then
      if #st.presets < rules.MAX_PRESETS then
        st.presets[#st.presets + 1] = { name = name, attack = rules.copyAttack(st.attack) }
        st.active = #st.presets
        app.say("Saved " .. name)
      end
    elseif st.presets[s.editing] then
      st.presets[s.editing].name = name
    end
    setEditing(false)
  elseif id == "pcancel" then
    setEditing(false)
  elseif id == "pfield" then
    -- The field swallows the tap. On a phone it also brings the keyboard
    -- back if the back button put it away mid-name.
    if s.editing then setEditing(s.editing) end
  end
  -- "sheet" swallows the tap and does nothing.
end

local function drawPresetRow(p, pr, i, x, y, w, h)
  -- While a name is being typed the rows are shown but inert. Loading,
  -- renaming another or deleting one mid-edit would shift the indexes under
  -- the edit and put the new name on the wrong preset.
  local s = S()
  local live = s.editing == false
  local a = live and 1 or 0.4
  local active = i == app.st.active
  if ui.isDown("pload", i) then ui.box(p.sunken, x, y, w, h, 10)
  elseif active then ui.box(ui.mix(p.panel, p.accent, 0.10), x, y, w, h, 10, a) end
  if active then ui.box(p.accent, x, y + 8, 3, h - 16, 1.5, a) end
  if live then
    local t = ui.target("pload", i, x, y, w, h)
    if t then t.shown = pr.name end
  end

  local right = w - 96
  ui.txt(ui.fit(pr.name, ui.BODY + 2, right - 16, "bold"), x + 14, y + 6, ui.BODY + 2, active and p.accent or p.ink, a, "left", "bold")
  ui.txt(ui.fit(rules.summary(pr.attack), ui.LABEL + 1, right - 16), x + 14, y + 28, ui.LABEL + 1, p.inkDim, a)
  if not live then return end

  if s.confirmDelete == i then
    ui.button(p, "pdel", i, x + w - 84, y + (h - 34) * 0.5, 80, 34, "Delete", ui.BODY, "solid", p.crit, true)
  else
    ui.button(p, "prename", i, x + w - 84, y + (h - 38) * 0.5, 40, 38, "✎", ui.NUM - 2, "quiet", p.inkDim, true)
    ui.button(p, "pdel", i, x + w - 42, y + (h - 38) * 0.5, 40, 38, "×", ui.NUM, "quiet", p.inkDim, true)
  end
end

local function drawNameEditor(p, x, y, w, h)
  local s, st = S(), app.st
  local title = s.editing == "new" and "Name the new preset"
    or ("Rename " .. ((st.presets[s.editing] or {}).name or ""))
  ui.caps(ui.fit(title, 10.5, w - 32), x + 16, y, 10.5, p.inkDim)

  local fx, fy, fw, fh = x + 16, y + ui.th(ui.LABEL) + 6, w - 32 - 150, 44
  ui.box(p.sunken, fx, fy, fw, fh, 10)
  ui.outline(p.accent, fx, fy, fw, fh, 10, 1.5, 1)
  local t = ui.target("pfield", 0, fx, fy, fw, fh)
  if t then t.shown = s.nameBuf end

  local shown = ui.fit(s.nameBuf, ui.BODY + 1, fw - 26)
  if s.nameFresh and s.nameBuf ~= "" then
    -- The suggestion is selected: the first key replaces it.
    ui.box(p.barLow, fx + 10, fy + 11, ui.tw(shown, ui.BODY + 1) + 4, fh - 22, 3)
  end
  ui.txtIn(shown, fx + 12, fy, fh, ui.BODY + 1, p.ink, 1)
  if math.floor(app.clock / 0.5) % 2 == 0 and not s.nameFresh then
    local cx = fx + 12 + ui.tw(shown, ui.BODY + 1) + 1
    ui.box(p.accent, cx, fy + 11, 2, fh - 22, 0)
  end

  ui.button(p, "pcommit", 0, fx + fw + 10, fy, 70, fh, "Save", ui.BODY + 1, "solid", p.accent, true)
  ui.button(p, "pcancel", 0, fx + fw + 86, fy, 64, fh, "Cancel", ui.BODY, "quiet", p.inkDim, true)
  return y + h
end

function sheet.draw(p)
  local s, st = S(), app.st
  -- The backdrop covers the whole window, notch and navigation bar included.
  local ww, wh = love.graphics.getWidth() / ui.S, love.graphics.getHeight() / ui.S
  ui.box(p.bg, 0, 0, ww, wh, 0, 0.74)
  ui.target("backdrop", 0, 0, 0, ww, wh)

  local n = #st.presets
  local editing = s.editing ~= false
  local rowH, headH = 54, 58
  local editH = editing and 92 or 0
  local listH = math.max(1, n) * rowH
  local footH = editing and 0 or 74
  local h = headH + editH + listH + footH + 8
  local x, w = ui.COLX, ui.COL_W
  local y = editing and ui.TOP + 68 or ui.VH - 14 - h

  ui.box(p.panel, x, y, w, h, 16)
  ui.outline(p.edge, x, y, w, h, 16, 1, 1)
  ui.target("sheet", 0, x, y, w, h)

  ui.txtIn("Attack presets", x + 16, y + 2, headH, 24, p.ink, 1, "left", "display")
  ui.txtIn(n .. " of " .. rules.MAX_PRESETS, x + 22 + ui.tw("Attack presets", 24, "display"), y + 4, headH,
           ui.LABEL, p.inkDim, 1, "left", "mono")
  ui.button(p, "pclose", 0, x + w - 84, y + 12, 72, 34, "Close", ui.BODY, "quiet", p.inkDim, true)
  local cy = y + headH

  if editing then cy = drawNameEditor(p, x, cy, w, editH) end

  if n == 0 then
    ui.txtIn("No presets yet. Save the attack you are editing", x + w * 0.5, cy, rowH * 0.6,
             ui.LABEL, p.inkDim, 1, "center")
    ui.txtIn("to reuse it here and on the Attack tab.", x + w * 0.5, cy + rowH * 0.4, rowH * 0.6,
             ui.LABEL, p.inkDim, 1, "center")
  end
  for i, pr in ipairs(st.presets) do
    drawPresetRow(p, pr, i, x + 8, cy, w - 16, rowH - 4)
    cy = cy + rowH
  end

  if not editing then
    local fy = y + h - footH + 6
    local room = n < rules.MAX_PRESETS
    local bw = w - 32
    if session.edited(st) then
      local half = (bw - 10) * 0.5
      ui.button(p, "psave", 0, x + 16, fy, half, 50, "Save as new", ui.BODY + 1, "solid", p.accent, room)
      ui.button(p, "pupdate", 0, x + 16 + half + 10, fy, half, 50, "Update " .. st.presets[st.active].name,
                ui.BODY + 1, "outline", p.accent, true)
    else
      ui.button(p, "psave", 0, x + 16, fy, bw, 50, room and "Save as new" or "Eight presets is the limit",
                ui.BODY + 1, "solid", p.accent, room)
    end
  end
end

return sheet
