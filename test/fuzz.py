#!/usr/bin/env python3
"""Drive the app's input handlers with thousands of random presses, holds,
drags, wheel turns, keys and typed text, and check every invariant after each
frame. See fuzz_driver.lua for what is checked.

The input mapping itself is covered by tapmap.py with real OS events; this
calls the handlers directly, in window units, so it can go fast and reach
deep states. The input comes from a fixed seed; the app still runs on real
frame time, so two runs differ a little in what the input reaches, and the
coverage floors at the end sit well below what a run gets to.

    python3 test/fuzz.py [frames]

The coverage floors are set for the default 20,000 frames; a much shorter run
checks every invariant but may stop at a floor.
"""
import os
import shutil
import subprocess
import sys
import tempfile

TMP = os.path.join(tempfile.gettempdir(), "dice-and-damage-tests")

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.environ.get("GAME_DIR", os.path.join(os.path.dirname(HERE), "game"))
frames = int(sys.argv[1]) if len(sys.argv) > 1 else 20000

tag = os.environ.get("TAG", "")
work = f"{TMP}/love-fuzz{tag}/game"
shutil.rmtree(os.path.dirname(work), ignore_errors=True)
shutil.copytree(GAME, work)
driver = open(os.path.join(HERE, "fuzz_driver.lua")).read().replace("FRAMES_HERE", str(frames)) \
    .replace("PROTO_HERE", os.path.join(HERE, "prototype-session.txt"))
open(os.path.join(work, "hooks.lua"), "w").write(driver)

identity = "dnd-dice-and-damage-fuzz"
conf = open(os.path.join(work, "conf.lua")).read()
conf = conf.replace('t.identity = "dnd-dice-and-damage"', f't.identity = "{identity}"')
conf = conf.replace("t.window.vsync     = 1", "t.window.vsync     = 0")
open(os.path.join(work, "conf.lua"), "w").write(conf)
shutil.rmtree(os.path.expanduser(f"~/.local/share/love/{identity}"), ignore_errors=True)

env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1")
cmd = ["xvfb-run", "-a", "-s", "-screen 0 600x1000x24", "love", work]
log = f"{TMP}/love-fuzz{tag}.log"
with open(log, "w") as out:
    try:
        subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, timeout=3000, env=env)
    except subprocess.TimeoutExpired:
        out.write("FUZZ TIMEOUT\n")
lines = open(log).read().splitlines()
print("\n".join(l for l in lines if l.startswith(("FUZZ", "v=", "preset=", "bonus=")) or "rror" in l)[-4000:])
sys.exit(0 if any("all invariants held" in l for l in lines) else 1)
