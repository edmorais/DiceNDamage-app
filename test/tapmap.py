#!/usr/bin/env python3
"""Tap every control on every screen through real input, check each tap lands
on the control under it and reaches that control's action, then walk the
cross-tab behaviour and the gestures. See tapmap_driver.lua for the layers.

    python3 test/tapmap.py [mouse|touch] [WIDTHxHEIGHT]

mouse drives the X pointer with xdotool; touch pushes fingers in window units
into LOVE's event queue, with the istouch mouse events SDL adds to each.
"""
import os
import shutil
import subprocess
import sys
import tempfile

TMP = os.path.join(tempfile.gettempdir(), "dice-and-damage-tests")

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.environ.get("GAME_DIR", os.path.join(os.path.dirname(HERE), "game"))

mode = sys.argv[1] if len(sys.argv) > 1 else "mouse"
size = sys.argv[2] if len(sys.argv) > 2 else "390x844"
assert mode in ("mouse", "touch")
w, h = (int(v) for v in size.split("x"))
tag = f"{mode}-{size}" + os.environ.get("TAG", "")
work = f"{TMP}/love-tapmap-{tag}/game"
shutil.rmtree(os.path.dirname(work), ignore_errors=True)
shutil.copytree(GAME, work)

hooks = open(os.path.join(GAME, "hooks.lua")).read()
for name in ("hooks.load", "hooks.update", "hooks.frame", "hooks.note"):
    assert f"function {name}(" in hooks, f"game/hooks.lua must declare {name} for the driver to replace"
driver = open(os.path.join(HERE, "tapmap_driver.lua")).read().replace("MODE_HERE", mode)
open(os.path.join(work, "hooks.lua"), "w").write(driver)

identity = f"dnd-dice-and-damage-tapmap-{mode}"
conf = open(os.path.join(work, "conf.lua")).read()
conf = conf.replace("t.window.width     = 390", f"t.window.width     = {w}")
conf = conf.replace("t.window.height    = 844", f"t.window.height    = {h}")
conf = conf.replace('t.identity = "dnd-dice-and-damage"', f't.identity = "{identity}"')
conf = conf.replace("t.window.resizable = true", "t.window.resizable = false")
open(os.path.join(work, "conf.lua"), "w").write(conf)
shutil.rmtree(os.path.expanduser(f"~/.local/share/love/{identity}"), ignore_errors=True)

env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1")
cmd = ["xvfb-run", "-a", "-s", f"-screen 0 {w + 200}x{h + 200}x24", "love", work]
log = f"{TMP}/love-tapmap-{tag}.log"
with open(log, "w") as out:
    try:
        subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, timeout=3000, env=env)
    except subprocess.TimeoutExpired:
        out.write("TAPMAP TIMEOUT\n")
lines = open(log).read().splitlines()
print("\n".join(l for l in lines if l.startswith(("TAPMAP", "  ")) or "rror" in l))
sys.exit(0 if any(" 0 failures" in l for l in lines) else 1)
