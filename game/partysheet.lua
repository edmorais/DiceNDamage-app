--[[
  partysheet.lua -- the party: switch characters, add, rename, recolour and
  delete them, and move them in and out of files.

  Opened from the character's name at the top of the screen. Each character
  keeps its own presets and its own working attack; switching brings back
  what that character was last holding. The situation (enemy AC, roll mode,
  the ability check) stays put: it belongs to the fight, not the character.

  Files are the web app's (see store.lua):

    Export character   writes exports/<name>.json and copies it
    Export party       writes exports/dice-and-damage-party.json and copies it
    Paste              reads a character file, a party file or a session.txt
                       from the clipboard
    drop a file        the same, on a desktop

  Before an import changes anything, the sheet says what the file holds and
  asks: Add, Replace the character with the same name, or (for a party file)
  Replace the party.

  Modes: "list", "edit" (a name and a dice colour) and "import".
--]]

local app = require("app")
local ui = require("ui")
local rules = require("rules")
local store = require("store")

local lg = love.graphics
local party = {}

local function P() return app.party end

local function setTyping(on)
  if love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, on) end
end

function party.open()
  local s = P()
  s.open, s.mode, s.confirmDelete, s.import = true, "list", 0, nil
  setTyping(false)
end

function party.close()
  local s = P()
  if s.mode == "edit" then setTyping(false) end
  s.open, s.mode, s.confirmDelete, s.import = false, "list", 0, nil
end

function party.isEditing() return P().open and P().mode == "edit" end

local function startEdit(idx)
  local s, st = P(), app.st
  s.mode, s.editIdx, s.confirmDelete = "edit", idx, 0
  if idx == "new" then
    s.nameBuf = store.uniqueName(st.party, "New character")
    -- The first dice colour no one has yet.
    local used = {}
    for _, c in ipairs(st.party) do used[c.color] = true end
    s.color = 7
    for k = 1, #store.COLORS do if not used[k] then s.color = k break end end
  else
    s.nameBuf, s.color = st.party[idx].name, st.party[idx].color
  end
  s.nameFresh = true
  setTyping(true)
end

function party.type(text)
  local s = P()
  if not party.isEditing() or type(text) ~= "string" then return end
  if s.nameFresh then s.nameBuf, s.nameFresh = "", false end
  local n, out = rules.length(s.nameBuf), { s.nameBuf }
  for cp in rules.codepoints(text) do
    if n >= rules.NAME_MAX then break end
    if cp >= 32 and cp ~= 127 then
      out[#out + 1] = rules.encodeCodepoint(cp)
      n = n + 1
    end
  end
  s.nameBuf = table.concat(out)
end

function party.backspace()
  local s = P()
  if not party.isEditing() then return end
  if s.nameFresh then s.nameBuf, s.nameFresh = "", false return end
  s.nameBuf = rules.dropLast(s.nameBuf)
end

-- ---------------------------------------------------------------- files

local EXPORTS = "exports"

local function export(name, text)
  local okay = pcall(love.filesystem.createDirectory, EXPORTS)
  local wrote = okay and love.filesystem.write(EXPORTS .. "/" .. name, text)
  local copied = pcall(love.system.setClipboardText, text)
  if wrote and copied then app.say("Saved " .. name .. " and copied it")
  elseif wrote then app.say("Saved " .. name)
  elseif copied then app.say("Copied " .. name .. " to the clipboard")
  else app.say("Could not save " .. name) end
  return wrote, copied
end

function party.exportCharacter()
  local c = store.char(app.st)
  return export(store.slug(c.name) .. ".json", store.characterFile(c))
end

function party.exportParty()
  return export("dice-and-damage-party.json", store.partyFile(app.st))
end

--- Shows what a file holds and waits for Add or Replace.
function party.offer(text, filename)
  local s = P()
  s.open, s.mode, s.confirmDelete = true, "import", 0
  s.import = store.parseImport(text, filename)
  setTyping(false)
end

function party.paste()
  local okay, text = pcall(love.system.getClipboardText)
  if not okay or type(text) ~= "string" or not text:match("%S") then
    app.say("The clipboard is empty")
    return
  end
  party.offer(text, "")
end

local function importNames(chars)
  local names = {}
  for _, c in ipairs(chars) do names[#names + 1] = c.name end
  return table.concat(names, ", ")
end

local function collides(chars)
  for _, c in ipairs(chars) do
    for _, o in ipairs(app.st.party) do
      if o.name:lower() == c.name:lower() then return true end
    end
  end
  return false
end

-- ---------------------------------------------------------------- actions

function party.action(id, arg)
  local s, st = P(), app.st
  if id == "qback" or id == "qclose" then
    party.close()
  elseif s.mode == "edit" then
    if id == "qsave" then
      local name = rules.sanitizeName(s.nameBuf)
      if s.editIdx == "new" then
        local c = store.blank(name ~= "" and name or "New character")
        c.attack = rules.copyAttack(st.attack)
        c.color = s.color
        local i = store.add(st, c)
        if i then
          store.switch(st, i)
          app.say("Added " .. st.party[i].name)
        end
      elseif st.party[s.editIdx] then
        if name ~= "" then store.rename(st, s.editIdx, name) end
        st.party[s.editIdx].color = s.color
        st.seeded = false
      end
      s.mode = "list"
      setTyping(false)
    elseif id == "qcancel" then
      s.mode = "list"
      setTyping(false)
    elseif id == "qcolor" then
      s.color = arg
    elseif id == "qfield" then
      setTyping(true)
    end
  elseif s.mode == "import" then
    local r = s.import
    if id == "qadd" or id == "qreplace" or id == "qparty" then
      if r and r.characters then
        local mode = id == "qadd" and "add" or (id == "qreplace" and "replace" or "party")
        local added, replaced, skipped = store.applyImport(st, r.characters, mode)
        local parts = {}
        if added > 0 then parts[#parts + 1] = added .. " added" end
        if replaced > 0 then parts[#parts + 1] = replaced .. " replaced" end
        if skipped > 0 then parts[#parts + 1] = skipped .. " skipped, the party is full" end
        app.say(#parts > 0 and table.concat(parts, ", ") or "Nothing imported")
        if mode == "party" then store.switch(st, 1) end
      end
      s.mode, s.import = "list", nil
    elseif id == "qcancel" then
      s.mode, s.import = "list", nil
    end
  else
    if id == "qpick" then
      if store.switch(st, arg) then
        party.close()
        app.say("Playing " .. st.party[arg].name)
      end
    elseif id == "qedit" then
      if st.party[arg] then startEdit(arg) end
    elseif id == "qdel" then
      if not st.party[arg] then return end
      if s.confirmDelete ~= arg then s.confirmDelete = arg return end
      local name = st.party[arg].name
      store.delete(st, arg)
      s.confirmDelete = 0
      app.say("Deleted " .. name)
    elseif id == "qnew" then
      if #st.party < store.MAX_CHARACTERS then startEdit("new") end
    elseif id == "qexport" then
      party.exportCharacter()
    elseif id == "qexportall" then
      party.exportParty()
    elseif id == "qpaste" then
      party.paste()
    end
  end
  if id ~= "qdel" then s.confirmDelete = 0 end
end

-- ---------------------------------------------------------------- drawing

--- A character's badge: a disc in its dice colour with its initial.
function party.emblem(p, c, cx, cy, r)
  local col = store.COLORS[c.color] and store.COLORS[c.color].rgb or store.COLORS[7].rgb
  ui.set(col, 1)
  lg.circle("fill", cx, cy, r, 40)
  ui.set(ui.mix(col, { 1, 1, 1 }, 0.35), 0.5)
  lg.circle("fill", cx - r * 0.25, cy - r * 0.3, r * 0.42, 24)
  ui.set(col, 1)
  lg.circle("fill", cx + r * 0.06, cy + r * 0.08, r * 0.8, 32)
  ui.set(p.accent, 0.6)
  lg.setLineWidth(1)
  lg.circle("line", cx, cy, r, 40)
  local initial = ""
  for cp in rules.codepoints(c.name) do initial = rules.encodeCodepoint(cp) break end
  local light = c.color == 8
  local size = r * 1.1
  ui.txt(initial, cx, cy - ui.th(size, "display") * 0.5, size, light and { 0.16, 0.13, 0.09 } or { 0.96, 0.93, 0.85 },
         1, "center", "display")
end

local function drawRow(p, c, i, x, y, w, h)
  local s, st = P(), app.st
  local current = i == st.current
  if ui.isDown("qpick", i) then ui.box(p.sunken, x, y, w, h, 12)
  elseif current then ui.box(ui.mix(p.panel, p.accent, 0.10), x, y, w, h, 12) end
  local t = ui.target("qpick", i, x, y, w, h)
  if t then t.shown = c.name end
  party.emblem(p, c, x + 24, y + h * 0.5, 16)
  local right = w - 100
  ui.txt(ui.fit(c.name, ui.BODY + 2, right - 48, "bold"), x + 50, y + 6, ui.BODY + 2,
         current and p.accent or p.ink, 1, "left", "bold")
  local sub = (c.note ~= "" and (c.note .. " · ") or "") .. #c.presets .. (#c.presets == 1 and " preset" or " presets")
  ui.txt(ui.fit(sub, ui.LABEL + 1, right - 48), x + 50, y + 26, ui.LABEL + 1, p.inkDim)
  if s.confirmDelete == i then
    ui.button(p, "qdel", i, x + w - 84, y + (h - 34) * 0.5, 80, 34, "Delete", ui.BODY, "solid", p.crit, true)
  else
    ui.button(p, "qedit", i, x + w - 84, y + (h - 38) * 0.5, 40, 38, "✎", ui.NUM - 2, "quiet", p.inkDim, true)
    ui.button(p, "qdel", i, x + w - 42, y + (h - 38) * 0.5, 40, 38, "×", ui.NUM, "quiet", p.inkDim, true)
  end
end

local function drawEditor(p, x, y, w)
  local s, st = P(), app.st
  local title = s.editIdx == "new" and "Name the new character"
    or ("Edit " .. ((st.party[s.editIdx] or {}).name or ""))
  ui.caps(ui.fit(title, 10.5, w - 32), x + 16, y, 10.5, p.inkDim)
  local fx, fy, fw, fh = x + 16, y + 20, w - 32 - 150, 44
  ui.box(p.sunken, fx, fy, fw, fh, 10)
  ui.outline(p.accent, fx, fy, fw, fh, 10, 1.5, 1)
  local t = ui.target("qfield", 0, fx, fy, fw, fh)
  if t then t.shown = s.nameBuf end
  local shown = ui.fit(s.nameBuf, ui.BODY + 2, fw - 26, "bold")
  if s.nameFresh and s.nameBuf ~= "" then
    ui.box(p.barLow, fx + 10, fy + 11, ui.tw(shown, ui.BODY + 2, "bold") + 4, fh - 22, 3)
  end
  ui.txtIn(shown, fx + 12, fy, fh, ui.BODY + 2, p.ink, 1, "left", "bold")
  if math.floor(app.clock / 0.5) % 2 == 0 and not s.nameFresh then
    ui.box(p.accent, fx + 12 + ui.tw(shown, ui.BODY + 2, "bold") + 1, fy + 11, 2, fh - 22, 0)
  end
  ui.button(p, "qsave", 0, fx + fw + 10, fy, 70, fh, "Save", ui.BODY + 1, "solid", p.accent, true)
  ui.button(p, "qcancel", 0, fx + fw + 86, fy, 64, fh, "Cancel", ui.BODY, "quiet", p.inkDim, true)

  local sy = fy + fh + 16
  ui.caps("Dice colour", x + 16, sy, 10.5, p.inkDim)
  sy = sy + 20
  local n = #store.COLORS
  local gap = 8
  local d = math.min(36, (w - 32 - gap * (n - 1)) / n)
  for k, col in ipairs(store.COLORS) do
    local cx = x + 16 + (k - 1) * (d + gap) + d * 0.5
    ui.set(col.rgb, 1)
    lg.circle("fill", cx, sy + d * 0.5, d * 0.5 - 2, 32)
    if k == s.color then
      ui.set(p.accent, 1)
      lg.setLineWidth(2.5)
      lg.circle("line", cx, sy + d * 0.5, d * 0.5 + 1, 32)
      lg.setLineWidth(1)
    end
    local tt = ui.target("qcolor", k, cx - d * 0.5, sy, d, d)
    if tt and k == s.color then tt.shown = "on" end
  end
  return sy + d + 14
end

local function drawImport(p, x, y, w)
  local s = P()
  local r = s.import or {}
  local cx, cw = x + 16, w - 32
  if r.error then
    ui.txt(ui.fit(r.error, ui.BODY, cw), cx, y, ui.BODY, p.crit)
    y = y + 30
    ui.button(p, "qcancel", 0, cx, y, cw, 46, "Back", ui.BODY + 1, "outline", p.accent, true)
    return y + 60
  end
  local kinds = { character = "A character file", party = "A party file", session = "The app's session.txt" }
  local n = #r.characters
  ui.txt(kinds[r.kind] or "A file", cx, y, ui.BODY + 1, p.ink, 1, "left", "bold")
  y = y + 24
  ui.txt(ui.fit(n .. (n == 1 and " character: " or " characters: ") .. importNames(r.characters), ui.BODY, cw),
         cx, y, ui.BODY, p.inkDim)
  y = y + 30
  local half = (cw - 10) * 0.5
  ui.button(p, "qadd", 0, cx, y, half, 46, "Add", ui.BODY + 1, "solid", p.accent, true)
  if r.kind == "party" then
    ui.button(p, "qparty", 0, cx + half + 10, y, half, 46, "Replace the party", ui.BODY + 1, "outline", p.crit, true)
    y = y + 56
    if collides(r.characters) then
      ui.button(p, "qreplace", 0, cx, y, half, 46, "Replace same names", ui.BODY, "outline", p.accent, true)
      ui.button(p, "qcancel", 0, cx + half + 10, y, half, 46, "Cancel", ui.BODY, "quiet", p.inkDim, true)
    else
      ui.button(p, "qcancel", 0, cx, y, cw, 46, "Cancel", ui.BODY, "quiet", p.inkDim, true)
    end
  else
    local can = collides(r.characters)
    ui.button(p, "qreplace", 0, cx + half + 10, y, half, 46, "Replace " .. r.characters[1].name, ui.BODY,
              "outline", p.accent, can)
    y = y + 56
    ui.button(p, "qcancel", 0, cx, y, cw, 46, "Cancel", ui.BODY, "quiet", p.inkDim, true)
  end
  return y + 56
end

local ROW_H, HEAD_H = 48, 58

function party.draw(p)
  local s, st = P(), app.st
  local ww, wh = lg.getWidth() / ui.S, lg.getHeight() / ui.S
  ui.box(p.bg, 0, 0, ww, wh, 0, 0.74)
  ui.target("qback", 0, 0, 0, ww, wh)

  local x, w = ui.COLX, ui.COL_W
  local n = #st.party
  local h
  if s.mode == "edit" then h = HEAD_H + 20 + 44 + 16 + 20 + 36 + 14 + 8
  elseif s.mode == "import" then h = HEAD_H + ((s.import or {}).error and 90 or 166) + 8
  else h = HEAD_H + n * ROW_H + 132 end
  local y = s.mode == "edit" and ui.TOP + 68 or ui.VH - 14 - h

  ui.box(p.panel, x, y, w, h, 18)
  ui.outline(p.edge, x, y, w, h, 18, 1, 1)
  ui.target("qsheet", 0, x, y, w, h)

  local title = s.mode == "import" and "Import" or "The party"
  ui.txtIn(title, x + 16, y + 2, HEAD_H, 24, p.ink, 1, "left", "display")
  if s.mode == "list" then
    ui.txtIn(n .. " of " .. store.MAX_CHARACTERS, x + 22 + ui.tw(title, 24, "display"), y + 4, HEAD_H,
             ui.LABEL, p.inkDim, 1, "left", "mono")
  end
  ui.button(p, "qclose", 0, x + w - 84, y + 12, 72, 34, "Close", ui.BODY, "quiet", p.inkDim, true)
  local cy = y + HEAD_H

  if s.mode == "edit" then
    drawEditor(p, x, cy, w)
  elseif s.mode == "import" then
    drawImport(p, x, cy, w)
  else
    for i, c in ipairs(st.party) do
      drawRow(p, c, i, x + 8, cy, w - 16, ROW_H - 4)
      cy = cy + ROW_H
    end
    local fy = y + h - 132 + 6
    local half = (w - 32 - 10) * 0.5
    ui.button(p, "qnew", 0, x + 16, fy, half, 46, #st.party < store.MAX_CHARACTERS and "New character"
              or "Twelve is the limit", ui.BODY + 1, "solid", p.accent, #st.party < store.MAX_CHARACTERS)
    ui.button(p, "qpaste", 0, x + 26 + half, fy, half, 46, "Paste a file", ui.BODY + 1, "outline", p.accent, true)
    fy = fy + 54
    ui.button(p, "qexport", 0, x + 16, fy, half, 40, "Export " .. store.char(st).name, ui.BODY, "outline", p.accent2, true)
    ui.button(p, "qexportall", 0, x + 26 + half, fy, half, 40, "Export party", ui.BODY, "outline", p.accent2, true)
    local os_ = love.system and love.system.getOS() or ""
    local hint = (os_ == "Android" or os_ == "iOS")
      and "Exports are copied to the clipboard; Paste reads one back."
      or "Exports go to the clipboard and exports/. Drop a file to import."
    ui.txt(ui.fit(hint, ui.LABEL, w - 32), x + w * 0.5, fy + 46, ui.LABEL, p.inkDim, 1, "center")
  end
end

return party
