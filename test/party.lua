--[[
  Logic tests for json.lua and store.lua: the party, its limits, and every
  file format shared with the web app. Plain LuaJIT, no LOVE:

      luajit test/party.lua

  The expected file text is written out by hand from the web app's
  src/store.js (characterFile is JSON.stringify(..., null, 2) plus a newline,
  keys in the order its tc() builds them), not produced by the code under
  test.
--]]

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = dir .. "/../game/?.lua;" .. package.path

local json = require("json")
local store = require("store")
local rules = require("rules")
local session = require("session")

local checks = 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then error(msg, 2) end
end
local function eq(a, b, msg)
  checks = checks + 1
  if a ~= b then error(msg .. "\n  got:  " .. tostring(a) .. "\n  want: " .. tostring(b), 2) end
end

-- ---------------------------------------------------------------- json

do
  local v = json.decode('{"a": [1, 2, {"b": "x\\u00e7\\ud83d\\udde1"}], "t": true, "f": false, "z": null, "n": -12.5e1}')
  eq(v.a[3].b, "xç🗡", "escapes and a surrogate pair decode to UTF-8")
  ok(v.t == true and v.f == false and v.z == json.null and v.n == -125, "literals and numbers")
  eq(v.a.n, 3, "arrays carry their length")
  for _, bad in ipairs({ "", "{", "[1,]", "{\"a\":1,}", "01", "\"\\ud83d\"", "\"a\nb\"", "[1] 2",
                         "\"\\x\"", "\"\255\"", "nul", string.rep("[", 40) .. string.rep("]", 40) }) do
    ok(json.decode(bad) == nil, "refused: " .. bad:sub(1, 20))
  end
  eq(json.encode(json.object({ "s", "n", "l" }, { s = "a\"b\\c\n\1é", n = 3, l = { n = 0 } })),
     '{"s":"a\\"b\\\\c\\n\\u0001é","n":3,"l":[]}', "encode escapes as JavaScript does")
  eq(json.encode({ n = 2, 1, json.object({ "k" }, { k = false }) }, 2), '[\n  1,\n  {\n    "k": false\n  }\n]',
     "indented like JSON.stringify(v, null, 2)")
end

-- ---------------------------------------------------------------- formats

local BRANNOC = [[
{
  "format": "dice-and-damage-character",
  "version": 1,
  "character": {
    "name": "Brannoc",
    "note": "Fighter 5 · Champion",
    "color": 0,
    "active": 0,
    "attack": {
      "bonus": 7,
      "dice": "1d8",
      "mod": 4,
      "attacks": 2,
      "crit": 0
    },
    "presets": [
      {
        "name": "Longsword",
        "attack": {
          "bonus": 7,
          "dice": "1d8",
          "mod": 4,
          "attacks": 2,
          "crit": 0
        }
      },
      {
        "name": "Greatsword",
        "attack": {
          "bonus": 8,
          "dice": "2d6",
          "mod": 5,
          "attacks": 2,
          "crit": 1
        }
      },
      {
        "name": "Handaxe, thrown",
        "attack": {
          "bonus": 7,
          "dice": "1d6",
          "mod": 4,
          "attacks": 2,
          "crit": 1
        }
      }
    ]
  }
}
]]

do
  local st = store.fresh()
  eq(#st.party, 3, "three example characters")
  eq(store.characterFile(st.party[1]), BRANNOC, "a character file is the web app's, byte for byte")
  local party = store.partyFile(st)
  ok(party:match('^{\n  "format": "dice%-and%-damage%-party",\n  "version": 1,\n  "characters": %[\n    {\n      "name": "Brannoc"'),
     "a party file starts as the web app's does")

  -- The proxy: the working attack, presets and active preset are the
  -- current character's.
  st.attack.bonus = 9
  eq(st.party[1].attack.bonus, 9, "st.attack is the first character's")
  store.switch(st, 2)
  eq(st.attack.bonus, 7, "switching brings back the second character's attack")
  eq(st.presets[1].name, "Rapier and Sneak Attack", "and its presets")
  st.active = 0
  eq(st.party[2].active, 0, "writes go to the current character")
  eq(rawget(st, "attack"), nil, "nothing is stored on the state itself")
  ok(not session.edited(st), "nothing loaded, nothing edited")
end

-- Round trips: the app's own save, and each file into a fresh party.
do
  local st = store.fresh()
  st.ac, st.rollMode, st.palIdx, st.tab, st.current = 22, rules.ADVANTAGE, 9, 3, 2
  st.party[2].attack.groups = { { n = 2, d = 6 }, { n = 1, d = 10 } }
  local text = store.encodeState(st)
  local back = store.decodeState(text)
  ok(back, "the app's save decodes")
  eq(store.encodeState(back), text, "and encodes to the same text")
  eq(back.palIdx, 9, "an eleven-scheme index survives")
  eq(back.attack.groups[2].d, 10, "the current character's working attack survives")
  local r = store.parseImport(text, "party.json")
  eq(r.kind, "party", "the app's save is itself a party file")
  eq(#r.characters, 3, "with every character")
end

-- Files the web app writes, as it writes them, including what it may hold
-- that the app must clamp or refuse.
do
  local r = store.parseImport(BRANNOC, "brannoc.json")
  eq(r.kind, "character", "a character file")
  local c = r.characters[1]
  eq(c.name .. "|" .. c.color .. "|" .. c.active .. "|" .. #c.presets, "Brannoc|1|1|3", "read with 1-based indexes")
  eq(c.presets[2].attack.crit, 2, "crit 1 in the file is the 19-20 range")

  local hostile = [[{"format":"dice-and-damage-party","version":1,"characters":[
    {"name":"  Ação   ⚔  ","note":"x","color":99,"active":7,"attack":{"bonus":99,"dice":"40d6","mod":"3","attacks":0,"crit":5},
     "presets":[{"name":"","attack":{"dice":"1d8"}},{"name":"No dice","attack":{}},{"name":"Ok","attack":{"groups":[{"n":3,"d":8},{"n":2,"d":7}]}}]},
    {"note":"no name"},
    {"name":"Twin"},{"name":"twin"}]}]]
  local p = store.parseImport(hostile, "")
  eq(p.kind, "party", "a hostile party file still reads")
  eq(#p.characters, 3, "the nameless character is dropped")
  local a = p.characters[1]
  eq(a.name, "Ação ⚔", "names are cleaned")
  eq(a.color, 8, "colour clamped")
  eq(#a.presets, 1, "presets without a name or dice are dropped")
  eq(a.active, 1, "active clamped to the presets there are")
  eq(a.attack.bonus .. "|" .. a.attack.mod .. "|" .. a.attack.attacks .. "|" .. a.attack.crit, "20|3|1|3",
     "attack fields clamped, a numeric string read as a number")
  eq(rules.encodeDice(a.attack.groups), "1d8", "too many dice: the default die")
  eq(rules.encodeDice(a.presets[1].attack.groups), "3d8", "an invalid die size is dropped from groups")

  local st = store.fresh()
  local added, replaced = store.applyImport(st, p.characters, "add")
  eq(added, 3, "three added")
  eq(st.party[5].name, "Twin", "")
  eq(st.party[6].name, "twin (2)", "names are kept unique ignoring case")

  local st2 = store.fresh()
  local r2 = store.parseImport(BRANNOC, "")
  r2.characters[1].note = "Replaced"
  local add2, rep2 = store.applyImport(st2, r2.characters, "replace")
  ok(add2 == 0 and rep2 == 1 and st2.party[1].note == "Replaced" and #st2.party == 3, "replace overwrites the same name")

  local st3 = store.fresh()
  store.applyImport(st3, store.parseImport(hostile, "").characters, "party")
  ok(#st3.party == 3 and st3.current == 1 and st3.party[1].name == "Ação ⚔", "replace the party")

  for _, bad in ipairs({ "", "   ", "{nope", '{"format":"other"}', '{"format":"dice-and-damage-party","characters":[]}',
                         "v=2\nbonus=3", "hello" }) do
    ok(store.parseImport(bad, "").error, "refused: " .. bad:sub(1, 24))
  end
end

-- session.txt: the prototype's file, as a character, and as a migration.
do
  local text = io.open(dir .. "/prototype-session.txt", "rb"):read("*a")
  local r = store.parseImport(text, "/path/to/session.txt")
  eq(r.kind, "session", "a session.txt is recognised")
  local c = r.characters[1]
  eq(c.name, "Imported character", "a file called session is not a name")
  eq(#c.presets, 4, "its four presets")
  eq(c.presets[4].name, "a🗡", "with the four-byte emoji name")
  eq(c.active, 4, "active=3 in the file is the fourth preset")
  eq(store.parseImport(text, "vex.txt").characters[1].name, "vex", "otherwise named after the file")

  local st = store.migrate(text)
  ok(st and #st.party == 1 and st.party[1].name == "My character", "migration makes one character")
  eq(st.ac .. "|" .. st.palIdx .. "|" .. st.tab, "10|4|2", "and keeps the settings (0-based in the file)")
  eq(rules.encodeDice(st.attack.groups), "2d12+1d8", "and the working attack")
end

-- Limits.
do
  local st = store.fresh()
  for k = 1, 20 do store.add(st, store.blank("Hero")) end
  eq(#st.party, store.MAX_CHARACTERS, "twelve at most")
  local seen = {}
  for _, c in ipairs(st.party) do
    ok(not seen[c.name:lower()], "names unique: " .. c.name)
    seen[c.name:lower()] = true
    ok(rules.length(c.name) <= rules.NAME_MAX, "names within 24 characters")
  end
  for k = #st.party, 1, -1 do store.delete(st, k) end
  ok(#st.party == 1 and st.party[1].name == "Adventurer", "the party is never empty")
  local long = store.uniqueName({ { name = "Twenty-four characters!!" } }, "Twenty-four characters!!")
  eq(long, "Twenty-four characte (2)", "a suffix fits inside the limit: 20 + 4, as the web app cuts")
  eq(store.slug("Sister Ilse"), "sister-ilse", "file names")
  eq(store.slug("⚔⚔"), "character", "a name with no letters still gets a file name")
end

print("party: " .. checks .. " checks passed")
