#!/usr/bin/env python3
"""Check that settings and presets survive a relaunch, through LOVE's own
save folder and the app's own save paths.

  1. Launch fresh, change things through the app's actions -- including a
     preset saved on the second character -- wait for the autosave and read
     party.json back from disk; then change one more thing and quit at once,
     so only the save on quit can have kept it.
  2. Launch again and report what came back.
  3. Launch over a party.json cut short: the app starts from the examples,
     keeps the file as party.unreadable.json and says so.
  4. Launch with only the first app's session.txt (one the Processing
     prototype wrote): it becomes one character, and is kept.
  5. Launch over a party file in the web app's format, written by hand.

Expectations come from the actions taken and from the web app's file
format, not from reading the app's state back into itself.

    python3 test/persist.py
"""
import os
import shutil
import json
import subprocess
import sys
import tempfile

TMP = os.path.join(tempfile.gettempdir(), "dice-and-damage-tests")

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), "game")
IDENT = "dnd-dice-and-damage-persist"
SAVE = os.path.expanduser(f"~/.local/share/love/{IDENT}")
work = f"{TMP}/love-persist/game"

COMMON = r'''
io.stdout:setvbuf("no")
function love.errorhandler(msg) print("PERSIST ERROR " .. debug.traceback(tostring(msg), 2)) os.exit(1) end
local app = require("app")
local session = require("session")
local hooks = {}
function hooks.load() end
function hooks.update(dt) end
function hooks.note(id, arg) end
local frame = 0
local function readFile(name)
  local s = love.filesystem.read(name)
  return s
end
'''

RUN1 = COMMON + r"""
local t0
function hooks.frame()
  frame = frame + 1
  local A = app.activate
  if frame == 3 then
    A("scheme", 0) A("scheme", 0)               -- scheme 3
    A("tab", 3)                                 -- Damage
    app.step("s.ac", 1, 1) app.step("s.ac", 1, 1) -- AC 17
    A("mode", 3)                                -- advantage
    A("party", 0) A("qpick", 2)                 -- Vex
    A("gadd", 0)                                -- 1d8 + 3d6 + 1d6
    A("presets", 0) A("psave", 0)
    love.textinput("Ação ⚔")
    A("pcommit", 0) A("pclose", 0)
    t0 = app.clock
  elseif t0 and app.clock - t0 > 1.2 and not app.autosaved then
    app.autosaved = true
    print("AUTOSAVED " .. tostring(readFile("party.json")):gsub("\n", " "))
    A("chart", 2)                               -- then quit before the autosave
    love.event.quit()
  end
end
return hooks
"""

REPORT = COMMON + r"""
local store = require("store")
function hooks.frame()
  frame = frame + 1
  if frame == 3 then
    print("STATE " .. store.encodeState(app.st):gsub("\n", " "))
    print("TOAST " .. tostring(app.toast))
    print("UNREADABLE " .. tostring(readFile("party.unreadable.json")):gsub("\n", " "))
    print("SESSION " .. tostring(readFile("session.txt") ~= nil))
    love.event.quit()
  end
end
return hooks
"""


def run(driver):
    shutil.rmtree(os.path.dirname(work), ignore_errors=True)
    shutil.copytree(GAME, work)
    open(os.path.join(work, "hooks.lua"), "w").write(driver)
    conf = open(os.path.join(work, "conf.lua")).read()
    conf = conf.replace('t.identity = "dnd-dice-and-damage"', f't.identity = "{IDENT}"')
    open(os.path.join(work, "conf.lua"), "w").write(conf)
    env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1")
    r = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 600x1000x24", "love", work],
                       capture_output=True, text=True, timeout=120, env=env)
    out = r.stdout + r.stderr
    if "PERSIST ERROR" in out:
        print(out)
        sys.exit(1)
    return {l.split(" ", 1)[0]: l.split(" ", 1)[1] if " " in l else "" for l in out.splitlines()
            if l.split(" ", 1)[0] in ("AUTOSAVED", "STATE", "TOAST", "UNREADABLE", "SESSION")}


checks, failures = 0, []


def expect(cond, msg):
    global checks
    checks += 1
    if not cond:
        failures.append(msg)


def load(text):
    try:
        return json.loads(text)
    except Exception:
        return None


# 1 and 2 -------------------------------------------------------------------
shutil.rmtree(SAVE, ignore_errors=True)
r1 = run(RUN1)
auto = load(r1.get("AUTOSAVED", "")) or {}
# party.json counts from 0, as the web app's files do: scheme 3 is pal 2,
# the Damage tab is tab 2, advantage is mode 2, Vex is character 1.
expect(auto.get("format") == "dice-and-damage-party" and auto.get("version") == 1, "party.json is not a party file")
ui, sit = auto.get("ui", {}), auto.get("situation", {})
expect(ui.get("pal") == 2 and ui.get("tab") == 2 and sit.get("ac") == 17 and sit.get("mode") == 2,
       f"autosave wrote ui {ui} situation {sit}")
expect(auto.get("current") == 1, f"autosave wrote current={auto.get('current')}")
chars = auto.get("characters", [])
vex = chars[1] if len(chars) > 1 else {}
expect(vex.get("name") == "Vex" and vex.get("attack", {}).get("dice") == "1d8+3d6+1d6",
       f"Vex's working attack: {vex.get('attack')}")
expect(len(vex.get("presets", [])) == 4 and vex["presets"][3] == {"name": "Ação ⚔", "attack": {
       "bonus": 7, "dice": "1d8+3d6+1d6", "mod": 4, "attacks": 1, "crit": 0}} and vex.get("active") == 3,
       f"Vex's presets: {vex.get('presets')} active {vex.get('active')}")
expect(chars and chars[0].get("attack", {}).get("dice") == "1d8", "Brannoc's attack changed with Vex's")
expect(ui.get("chart") == 0, "the chart changed before it was changed")

r2 = run(REPORT)
st2 = load(r2.get("STATE", "")) or {}
expect(st2.get("ui", {}).get("chart") == 1, "the change made just before quitting was lost")
expect(st2.get("characters") == chars and st2.get("current") == 1, "the party did not come back as saved")
expect(r2.get("TOAST") == "nil", "a readable party raised a toast: " + r2.get("TOAST", ""))

# 3 -------------------------------------------------------------------------
open(os.path.join(SAVE, "party.json"), "w").write('{"format":"dice-and-damage-party","version":1,"charac')
r3 = run(REPORT)
st3 = load(r3.get("STATE", "")) or {}
names3 = [c["name"] for c in st3.get("characters", [])]
expect(names3 == ["Brannoc", "Vex", "Sister Ilse"], f"an unreadable file did not start from the examples: {names3}")
expect(r3.get("UNREADABLE", "").startswith('{"format":"dice-and-damage-party"'), "the unreadable file was not kept")
expect("unreadable" in r3.get("TOAST", ""), "no toast for an unreadable file: " + str(r3.get("TOAST")))

# 4 -------------------------------------------------------------------------
# The first app's session.txt (here, one the Processing prototype wrote)
# becomes one character on the first launch, and is kept.
shutil.rmtree(SAVE, ignore_errors=True)
os.makedirs(SAVE)
proto = open(os.path.join(HERE, "prototype-session.txt"), encoding="utf-8").read()
open(os.path.join(SAVE, "session.txt"), "w", encoding="utf-8").write(proto)
r4 = run(REPORT)
st4 = load(r4.get("STATE", "")) or {}
c4 = st4.get("characters", [{}])
want_presets = [l.split("=", 1)[1].split("|")[0] for l in proto.splitlines() if l.startswith("preset=")]
expect(len(c4) == 1 and c4[0].get("name") == "My character", f"migration made {[c.get('name') for c in c4]}")
expect([p["name"] for p in c4[0].get("presets", [])] == want_presets, "the presets did not carry over")
expect(c4[0].get("attack", {}).get("dice") == "2d12+1d8" and c4[0].get("active") == 3, "the working attack did not")
expect(st4.get("situation", {}).get("ac") == 10 and st4.get("ui", {}).get("pal") == 3, "the settings did not")
expect(r4.get("SESSION") == "true", "session.txt was not kept")
expect("My character" in r4.get("TOAST", ""), "no word about the migration")

# 5 -------------------------------------------------------------------------
# A party file as the web app writes it, written out here by hand.
shutil.rmtree(SAVE, ignore_errors=True)
os.makedirs(SAVE)
web = """{
  "format": "dice-and-damage-party",
  "version": 1,
  "characters": [
    {
      "name": "Mira",
      "note": "Ranger 3",
      "color": 5,
      "active": -1,
      "attack": { "bonus": 6, "dice": "1d8+1d6", "mod": 3, "attacks": 2, "crit": 0 },
      "presets": [ { "name": "Longbow", "attack": { "bonus": 6, "dice": "1d8", "mod": 3, "attacks": 2, "crit": 0 } } ]
    }
  ]
}
"""
open(os.path.join(SAVE, "party.json"), "w").write(web)
r5 = run(REPORT)
st5 = load(r5.get("STATE", "")) or {}
c5 = st5.get("characters", [{}])[0]
expect(c5.get("name") == "Mira" and c5.get("color") == 5 and c5.get("active") == -1
       and c5.get("attack", {}).get("dice") == "1d8+1d6", f"the web app's party file came back as {c5}")
expect(st5.get("situation", {}).get("ac") == 15, "a party file without a situation did not get the default")

print(f"PERSIST {checks} checks, {len(failures)} failures")
for f in failures:
    print("  FAIL", f)
sys.exit(1 if failures else 0)
