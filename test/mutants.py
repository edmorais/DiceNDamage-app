#!/usr/bin/env python3
"""Check that the tests can fail: put known bugs back into scratch copies of
the game, one per copy, and require the test that should catch each one to
fail on it.

Several of these are bugs that really happened -- in the prototype or in the
first Android Dice Roller -- and the rest are the likeliest ways this port
could go wrong.

    python3 test/mutants.py            # every mutant, three at a time
    python3 test/mutants.py m1 f2      # just these
"""
import os
import shutil
import subprocess
import sys
import tempfile

TMP = os.path.join(tempfile.gettempdir(), "dice-and-damage-tests")

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), "game")

# name: (test, mode, [(file, old, new), ...])
MUTANTS = {
    "m1-no-scale": ("tapmap", "touch", [
        ("ui.lua", "return x / ui.S, y / ui.S", "return x, y")]),
    "m2-istouch-not-ignored": ("tapmap", "touch", [
        ("main.lua", "if istouch or button ~= 1 then return end", "if button ~= 1 then return end")]),
    "m3-plot-shares-chart-id": ("tapmap", "mouse", [
        ("calc.lua", 'ui.target("plot", 0, px - 8', 'ui.target("chart", 1, px - 8'),
        ("main.lua", 'if t and t.id == "plot" then', 'if t and t.id == "chart" then')]),
    "m4-crit-not-doubled": ("tapmap", "mouse", [
        ("main.lua", "st.doubleDice = r ~= nil and r.crit", "st.doubleDice = false")]),
    "m5-hold-never-repeats": ("tapmap", "mouse", [
        ("main.lua", "if press.t >= 0.42 then", "if press.t >= 99 then")]),
    "m6-no-lost-touch-watchdog": ("tapmap", "touch", [
        ("main.lua", "local LOST_TOUCH = 0.25", "local LOST_TOUCH = 1e9")]),
    "m7-handoff-edits-dice": ("tapmap", "mouse", [
        ("main.lua", "  showTab(app.DAMAGE)\n  app.views.damage:setDamage",
         "  showTab(app.DAMAGE)\n  st.attack = rules.copyAttack(st.attack) "
         "st.attack.groups[1].n = st.attack.groups[1].n + 1\n  app.views.damage:setDamage")]),
    "m8-lua-drops-second-value": ("tapmap", "touch", [
        ("main.lua", "  local dx, dy = ui.toDesign(x, y)\n  onPress(dx, dy, id)",
         "  onPress(ui.toDesign(x, y), id)")]),
    "m9-new-attack-rerolls-damage": ("tapmap", "mouse", [
        ("main.lua", "  elseif id == \"rollatk\" then\n    rollAttackFromCalculator()",
         "  elseif id == \"rollatk\" then\n    rollCurrent()")]),
    "m10-one-attack-for-everyone": ("tapmap", "mouse", [
        ("store.lua", "        local c = rawget(t, \"party\")[rawget(t, \"current\")]\n        return c and c[k]",
         "        local c = rawget(t, \"party\")[1]\n        return c and c[k]"),
        ("store.lua", "        rawget(t, \"party\")[rawget(t, \"current\")][k] = v",
         "        rawget(t, \"party\")[1][k] = v")]),
    "f4-duplicate-names-on-import": ("fuzz", None, [
        ("store.lua", "  c.name = store.uniqueName(st.party, c.name)\n  st.party[#st.party + 1] = c\n  st.seeded = false\n  return #st.party",
         "  st.party[#st.party + 1] = c\n  st.seeded = false\n  return #st.party")]),
    "f1-close-keeps-editing": ("fuzz", None, [
        ("sheet.lua", "  s.open, s.confirmDelete = false, 0\n  if s.editing then setEditing(false) end",
         "  s.open, s.confirmDelete = false, 0")]),
    "f2-no-name-limit": ("fuzz", None, [
        ("sheet.lua", "    if n >= rules.NAME_MAX then break end\n", "")]),
    "f3-raw-bytes-in-name": ("fuzz", None, [
        ("sheet.lua", "  s.nameBuf = table.concat(out)\nend",
         "  s.nameBuf = table.concat(out) .. (text:find('[\\128-\\255]') and text:sub(1, 1) or '')\nend")]),
}

wanted = [n for n in MUTANTS if not sys.argv[1:] or any(n.startswith(a) for a in sys.argv[1:])]


def start(name):
    test, mode, edits = MUTANTS[name]
    d = f"{TMP}/mutant-{name}/game"
    shutil.rmtree(os.path.dirname(d), ignore_errors=True)
    shutil.copytree(GAME, d)
    for f, old, new in edits:
        p = os.path.join(d, f)
        s = open(p, encoding="utf-8").read()
        assert s.count(old) == 1, f"{name}: the code to mutate in {f} has changed"
        open(p, "w", encoding="utf-8").write(s.replace(old, new))
    env = dict(os.environ, GAME_DIR=d, TAG="-" + name)
    if test == "tapmap":
        size = "1080x2400" if mode == "touch" else "390x844"
        cmd = ["python3", os.path.join(HERE, "tapmap.py"), mode, size]
    else:
        cmd = ["python3", os.path.join(HERE, "fuzz.py"), "6000"]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)


survivors = []
for k in range(0, len(wanted), 3):
    batch = [(n, start(n)) for n in wanted[k:k + 3]]
    for n, p in batch:
        out, _ = p.communicate()
        lines = out.splitlines()
        first = next((l.strip() for l in lines if "FAIL" in l), "")
        summary = next((l for l in lines if " checks, " in l), "")
        # A short fuzz run can miss the coverage floors; that is not a catch.
        coverage = any(m in first for m in ("did not reach", "barely used", "never edited"))
        caught = p.returncode != 0 and not coverage
        if not caught:
            survivors.append(n)
        print(f"{'caught  ' if caught else 'SURVIVED'} {n:28} {summary.replace('TAPMAP ', '')}")
        if first:
            print(f"         {first[:140]}")
print(f"MUTANTS {len(wanted) - len(survivors)} of {len(wanted)} caught")
sys.exit(1 if survivors else 0)
