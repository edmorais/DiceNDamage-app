--[[
  store.lua -- the party: characters, each with its own attack presets, and
  every file format the web app reads and writes. Plain Lua, no LOVE calls.

  A character is { name, note, color, presets, active, attack }:
    name     unique in the party (ignoring case), at most 24 characters
    note     a short line, class and level say, at most 32
    color    1..8, one of the web app's dice colours
    presets  up to 8 of { name, attack }
    active   the preset the working attack came from, 0 for none
    attack   the character's own working attack

  The app state keeps the party and, beside it, the situation (enemy AC, roll
  mode, the ability check) and the interface settings, which belong to the
  table rather than to a character. The working attack, the presets and the
  active preset are the current character's: st.attack, st.presets and
  st.active read and write straight through to it, so every screen written
  for one attack works unchanged for a party.

  Files, all compatible with the web app (src/store.js there):

    character   {"format":"dice-and-damage-character","version":1,"character":{...}}
    party       {"format":"dice-and-damage-party","version":1,"characters":[...]}
    web state   {"format":"dice-and-damage-web", ... "party":[...]}   read only
    session.txt the prototype's and the first app's save file           read only

  In the files, every index counts from 0 as the web app's do; this module is
  the only place that converts. The app's own save file, party.json, is a
  party file with the situation, the interface settings and the current
  character added, so it can itself be loaded into the web app as a party.
--]]

local rules = require("rules")
local session = require("session")
local json = require("json")

local store = {}

store.MAX_CHARACTERS = 12
store.NOTE_MAX = 32
store.VERSION = 1
store.FORMAT_CHARACTER = "dice-and-damage-character"
store.FORMAT_PARTY = "dice-and-damage-party"
store.FORMAT_WEB = "dice-and-damage-web"

-- The web app's dice colours, in its order.
store.COLORS = {
  { "Garnet", "7c1d2a" }, { "Emerald", "1c6248" }, { "Sapphire", "1f3d80" }, { "Amethyst", "5a2b7e" },
  { "Amber", "93600f" }, { "Teal", "11596a" }, { "Obsidian", "1d1d24" }, { "Bone", "d9cfb6" },
}
for _, c in ipairs(store.COLORS) do
  local h = c[2]
  c.rgb = { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

-- ---------------------------------------------------------------- characters

local function preset(name, ...) return { name = name, attack = rules.newAttack(...) } end

--- The web app's three examples. The first app's three default presets are
--- among theirs. newAttack's crit is 1-based.
function store.examples()
  local list = {
    { name = "Brannoc", note = "Fighter 5 · Champion", color = 1, presets = {
        preset("Longsword", 7, "1d8", 4, 2, 1), preset("Greatsword", 8, "2d6", 5, 2, 2),
        preset("Handaxe, thrown", 7, "1d6", 4, 2, 2) } },
    { name = "Vex", note = "Rogue 5", color = 2, presets = {
        preset("Rapier and Sneak Attack", 7, "1d8+3d6", 4, 1, 1), preset("Shortbow, Sneak Attack", 7, "1d6+3d6", 4, 1, 1),
        preset("Off-hand dagger", 7, "1d4", 0, 1, 1) } },
    { name = "Sister Ilse", note = "Paladin 5", color = 3, presets = {
        preset("Longsword and Smite", 7, "1d8+2d8", 4, 1, 1), preset("Longsword", 7, "1d8", 4, 2, 1),
        preset("Javelin", 7, "1d6", 4, 2, 1) } },
  }
  for _, c in ipairs(list) do
    c.active = 1
    c.attack = rules.copyAttack(c.presets[1].attack)
  end
  return list
end

function store.blank(name)
  return { name = name or "New character", note = "", color = 7, presets = {}, active = 0,
           attack = rules.newAttack() }
end

--- name, made unique in the party ignoring case, with " (2)" and so on.
--- `except` is the index of the character being renamed.
function store.uniqueName(party, name, except)
  local base = rules.sanitizeName(name)
  if base == "" then base = "Character" end
  local function taken(s)
    for i, c in ipairs(party) do
      if i ~= except and c.name:lower() == s:lower() then return true end
    end
    return false
  end
  if not taken(base) then return base end
  local k = 2
  while true do
    local tail = " (" .. k .. ")"
    local cut = base
    while rules.length(cut) + #tail > rules.NAME_MAX do cut = rules.dropLast(cut) end
    local s = cut:gsub("%s+$", "") .. tail
    if not taken(s) then return s end
    k = k + 1
  end
end

-- ---------------------------------------------------------------- state

local PROXIED = { attack = true, presets = true, active = true }

--- st.attack, st.presets and st.active are the current character's.
function store.attach(st)
  return setmetatable(st, {
    __index = function(t, k)
      if PROXIED[k] then
        local c = rawget(t, "party")[rawget(t, "current")]
        return c and c[k]
      end
    end,
    __newindex = function(t, k, v)
      if PROXIED[k] then
        rawget(t, "party")[rawget(t, "current")][k] = v
      else
        rawset(t, k, v)
      end
    end,
  })
end

function store.fresh()
  return store.attach({
    ac = 15, rollMode = rules.NORMAL, checkMod = 3, checkDc = 0, doubleDice = false,
    tab = 1, attackSub = 1, palIdx = 1, chart = 1, showCcdf = true,
    party = store.examples(), current = 1, seeded = true,
  })
end

function store.char(st) return st.party[st.current] end

function store.switch(st, i)
  if not st.party[i] then return false end
  st.current = i
  return true
end

function store.add(st, c)
  if #st.party >= store.MAX_CHARACTERS then return nil end
  c.name = store.uniqueName(st.party, c.name)
  st.party[#st.party + 1] = c
  st.seeded = false
  return #st.party
end

--- Removes a character; the party is never left empty.
function store.delete(st, i)
  if not st.party[i] then return false end
  table.remove(st.party, i)
  if #st.party == 0 then st.party[1] = store.blank("Adventurer") end
  if st.current > i then st.current = st.current - 1 end
  st.current = rules.clamp(st.current, 1, #st.party)
  st.seeded = false
  return true
end

function store.rename(st, i, name)
  local c = st.party[i]
  local clean = rules.sanitizeName(name)
  if not c or clean == "" then return false end
  c.name = store.uniqueName(st.party, clean, i)
  st.seeded = false
  return c.name
end

-- ---------------------------------------------------------------- to files

local function attackObject(a)
  return json.object({ "bonus", "dice", "mod", "attacks", "crit" }, {
    bonus = a.bonus, dice = rules.encodeDice(a.groups), mod = a.mod, attacks = a.attacks, crit = a.crit - 1 })
end

function store.characterObject(c)
  local presets = { n = #c.presets }
  for i, p in ipairs(c.presets) do
    presets[i] = json.object({ "name", "attack" }, { name = rules.sanitizeName(p.name), attack = attackObject(p.attack) })
  end
  return json.object({ "name", "note", "color", "active", "attack", "presets" }, {
    name = c.name, note = c.note, color = c.color - 1, active = c.active - 1,
    attack = attackObject(c.attack), presets = presets })
end

--- One character, as the web app's Save file writes it.
function store.characterFile(c)
  return json.encode(json.object({ "format", "version", "character" }, {
    format = store.FORMAT_CHARACTER, version = store.VERSION, character = store.characterObject(c) }), 2) .. "\n"
end

--- Everyone, as the web app's Save party writes it.
function store.partyFile(st)
  local list = { n = #st.party }
  for i, c in ipairs(st.party) do list[i] = store.characterObject(c) end
  return json.encode(json.object({ "format", "version", "characters" }, {
    format = store.FORMAT_PARTY, version = store.VERSION, characters = list }), 2) .. "\n"
end

--- The app's own save: a party file, plus the table's settings.
function store.encodeState(st)
  local list = { n = #st.party }
  for i, c in ipairs(st.party) do list[i] = store.characterObject(c) end
  return json.encode(json.object({ "format", "version", "characters", "current", "seeded", "situation", "ui" }, {
    format = store.FORMAT_PARTY, version = store.VERSION, characters = list,
    current = st.current - 1, seeded = st.seeded and true or false,
    situation = json.object({ "ac", "mode", "checkMod", "checkDc", "doubleDice" }, {
      ac = st.ac, mode = st.rollMode - 1, checkMod = st.checkMod, checkDc = st.checkDc, doubleDice = st.doubleDice }),
    ui = json.object({ "tab", "sub", "pal", "chart", "ccdf" }, {
      tab = st.tab - 1, sub = st.attackSub - 1, pal = st.palIdx - 1, chart = st.chart - 1, ccdf = st.showCcdf }),
  }), 2) .. "\n"
end

--- A file name from a character's name: "Sister Ilse" -> "sister-ilse".
function store.slug(name)
  local s = (name or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  s = s:sub(1, 40)
  return s ~= "" and s or "character"
end

-- ---------------------------------------------------------------- from files

local function int(v, lo, hi, fallback)
  if type(v) == "string" and v:match("^%s*%-?%d+%s*$") then v = tonumber(v) end
  if type(v) ~= "number" or v ~= math.floor(v) then return fallback end
  return rules.clamp(v, lo, hi)
end

--- An attack from a file, every field brought inside the limits.
function store.readAttack(o)
  if type(o) ~= "table" then o = {} end
  local a = {
    bonus = int(o.bonus, rules.BONUS_MIN, rules.BONUS_MAX, 5),
    mod = int(o.mod, rules.MOD_MIN, rules.MOD_MAX, 3),
    attacks = int(o.attacks, rules.ATTACKS_MIN, rules.ATTACKS_MAX, 1),
    crit = int(o.crit, 0, #rules.CRIT_MINS - 1, 0) + 1,
    groups = {},
  }
  if type(o.groups) == "table" then
    for _, g in ipairs(o.groups) do
      if #a.groups >= rules.MAX_GROUPS then break end
      if type(g) == "table" then
        local d, n = int(g.d, 0, 1000, 0), int(g.n, 0, 1000, 0)
        if rules.isSize(d) and n >= 1 then a.groups[#a.groups + 1] = { n = math.min(n, rules.MAX_DICE), d = d } end
      end
    end
  elseif type(o.dice) == "string" then
    a.groups = rules.parseDice(o.dice, rules.MAX_GROUPS, rules.MAX_DICE)
  end
  return rules.clampAttack(a)
end

local function readPreset(o)
  if type(o) ~= "table" then return nil end
  local name = rules.sanitizeName(o.name)
  if name == "" or type(o.attack) ~= "table" then return nil end
  local a = o.attack
  local hasDice = (type(a.groups) == "table" and #a.groups > 0) or type(a.dice) == "string"
  if not hasDice then return nil end
  return { name = name, attack = store.readAttack(a) }
end

--- A character from a file, or nil when it has no name.
function store.readCharacter(o)
  if type(o) ~= "table" then return nil end
  local name = rules.sanitizeName(o.name)
  if name == "" then return nil end
  local presets = {}
  if type(o.presets) == "table" then
    for _, p in ipairs(o.presets) do
      if #presets >= rules.MAX_PRESETS then break end
      local r = readPreset(p)
      if r then presets[#presets + 1] = r end
    end
  end
  local attack
  if type(o.attack) == "table" then attack = store.readAttack(o.attack)
  elseif presets[1] then attack = rules.copyAttack(presets[1].attack)
  else attack = rules.newAttack() end
  return {
    name = name,
    note = rules.sanitizeName(type(o.note) == "string" and o.note or "", store.NOTE_MAX),
    color = int(o.color, 0, #store.COLORS - 1, 6) + 1,
    presets = presets,
    active = int(o.active, -1, #presets - 1, -1) + 1,
    attack = attack,
  }
end

--- A session.txt as one character: its presets and working attack. Named
--- after the file unless the file is just "session".
function store.fromSession(text, filename)
  local s = session.fresh()
  if not session.decode(session.lines(text), s) then return nil end
  local base = (filename or ""):gsub("^.*[\\/]", ""):gsub("%.[^.]*$", "")
  local name = rules.sanitizeName(base)
  if name == "" or name:lower() == "session" then name = "Imported character" end
  return { name = name, note = "From the app", color = 7, presets = s.presets,
           active = s.active, attack = s.attack }, s
end

--- What a file holds: { kind = "character" | "party" | "session",
--- characters = {...} } or { error = "..." }. Nothing is changed yet.
function store.parseImport(text, filename)
  if type(text) ~= "string" or not text:match("%S") then return { error = "That file is empty." } end
  if #text > 2000000 then return { error = "That file is too large to be a party file." } end
  local body = text:gsub("^\239\187\191", "")
  if body:match("^%s*[{%[]") then
    local o = json.decode(body)
    if type(o) ~= "table" then return { error = "That file looks like JSON but can't be read. It may be cut short." } end
    if o.format == store.FORMAT_CHARACTER then
      local c = store.readCharacter(o.character)
      if not c then return { error = "That character file has no name." } end
      return { kind = "character", characters = { c } }
    end
    if o.format == store.FORMAT_PARTY or o.format == store.FORMAT_WEB then
      local list = (o.format == store.FORMAT_PARTY) and o.characters or o.party
      local out = {}
      if type(list) == "table" then
        for _, x in ipairs(list) do
          local c = store.readCharacter(x)
          if c then out[#out + 1] = c end
        end
      end
      if #out == 0 then return { error = "That party file has no characters in it." } end
      return { kind = "party", characters = out }
    end
    return { error = "That JSON isn't a Dice & Damage character or party file." }
  end
  local c = store.fromSession(body, filename)
  if c then return { kind = "session", characters = { c } } end
  return { error = "That isn't a Dice & Damage character, party or session.txt file." }
end

--- Puts imported characters into the party. mode is "add" (new names made
--- unique), "replace" (a character with the same name is overwritten, the
--- rest added) or "party" (the party becomes the file's).
function store.applyImport(st, chars, mode)
  local added, replaced, skipped = 0, 0, 0
  if mode == "party" then
    st.party = {}
    for _, c in ipairs(chars) do
      if #st.party >= store.MAX_CHARACTERS then skipped = skipped + 1
      else
        c.name = store.uniqueName(st.party, c.name)
        st.party[#st.party + 1] = c
        added = added + 1
      end
    end
    st.current = 1
    st.seeded = false
    return added, replaced, skipped
  end
  for _, c in ipairs(chars) do
    local found
    for i, o in ipairs(st.party) do if o.name:lower() == c.name:lower() then found = i end end
    if mode == "replace" and found then
      c.name = st.party[found].name
      st.party[found] = c
      replaced = replaced + 1
    elseif store.add(st, c) then
      added = added + 1
    else
      skipped = skipped + 1
    end
  end
  st.seeded = false
  return added, replaced, skipped
end

--- The app's own save file back into a state; nil if it isn't one.
function store.decodeState(text)
  local o = json.decode(text or "")
  if type(o) ~= "table" or o.format ~= store.FORMAT_PARTY or o.version ~= store.VERSION then return nil end
  local st = store.fresh()
  local party = {}
  if type(o.characters) == "table" then
    for _, x in ipairs(o.characters) do
      if #party >= store.MAX_CHARACTERS then break end
      local c = store.readCharacter(x)
      if c then
        c.name = store.uniqueName(party, c.name)
        party[#party + 1] = c
      end
    end
  end
  if #party == 0 then return nil end
  st.party = party
  st.current = int(o.current, 0, #party - 1, 0) + 1
  st.seeded = o.seeded == true
  local s, u = type(o.situation) == "table" and o.situation or {}, type(o.ui) == "table" and o.ui or {}
  st.ac = int(s.ac, rules.AC_MIN, rules.AC_MAX, 15)
  st.rollMode = int(s.mode, 0, 2, 1) + 1
  st.checkMod = int(s.checkMod, rules.CHECK_MOD_MIN, rules.CHECK_MOD_MAX, 3)
  st.checkDc = int(s.checkDc, 0, rules.DC_MAX, 0)
  st.doubleDice = s.doubleDice == true
  st.tab = int(u.tab, 0, 3, 0) + 1
  st.attackSub = int(u.sub, 0, 1, 0) + 1
  st.palIdx = int(u.pal, 0, store.SCHEMES - 1, 0) + 1
  st.chart = int(u.chart, 0, 1, 0) + 1
  st.showCcdf = u.ccdf ~= false
  return st
end

--- The first app's session.txt, from before characters: its presets become
--- one character and its settings carry over. nil if it isn't a session.
function store.migrate(text)
  local c, s = store.fromSession(text, "session.txt")
  if not c then return nil end
  c.name, c.note = "My character", ""
  local st = store.fresh()
  st.party = { c }
  st.current = 1
  st.seeded = false
  st.ac, st.rollMode, st.checkMod, st.checkDc, st.doubleDice = s.ac, s.rollMode, s.checkMod, s.checkDc, s.doubleDice
  st.tab, st.attackSub, st.palIdx, st.chart, st.showCcdf = s.tab, s.attackSub, s.palIdx, s.chart, s.showCcdf
  return st
end

store.SCHEMES = 11

return store
