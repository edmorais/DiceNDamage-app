#!/usr/bin/env python3
"""build_apk.py -- wrap the game in the official LÖVE for Android shell.

LÖVE ships an "embed" APK: the engine with an empty assets folder. This drops
game.love into it, rewrites the manifest so the result is a separate app rather
than a second copy of LÖVE, replaces the launcher icons, then aligns and signs,
and finally has Android's own tools read the result back.

The same script, with the same manifest patcher, built the Dice Roller. The
application id, label, icon and key are this app's own, so the two install
side by side.

The manifest changes are the interesting part. The stock shell is locked to
landscape and claims org.love2d.android for its application id, its dynamic
receiver permission and its androidx-startup provider authority. Installing it
next to a real LÖVE install, or next to the Damage Calculator built the same
way (the Damage Calculator, the Dice Roller), would fail on the duplicate
authority. So all three move to this app's own
id, and the orientation enum flips to portrait.

The activity's android:name is already fully qualified in the stock manifest
(org.love2d.android.GameActivity), so changing the application id does not
break the class lookup — that would be the trap if it were written as
".GameActivity".

Needs: zipalign, apksigner and aapt (Android build-tools, or apt install
apksigner zipalign aapt), any JDK for keytool, and Pillow for the icon.
"""
import os
import shutil
import struct
import subprocess
import sys
import zipfile

import axml
import icon

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), "game")
BUILD = os.path.join(HERE, "build")

SHELL_URL = ("https://github.com/love2d/love-android/releases/download/"
             "11.5a/love-11.5-android-embed.apk")
SHELL = os.path.join(BUILD, "love-embed.apk")

APP_ID    = "com.dndtools.diceanddamage"
APP_LABEL = "Dice & Damage"
# Bump both for every build handed out: a higher code installs over the last
# one, and App Info shows at a glance which build is on the phone.
VERSION_NAME = "1.1"
VERSION_CODE = 2

OUT = os.path.join(os.path.dirname(HERE), "DiceAndDamage.apk")

# Kept beside this script, not in build/: every later build must be signed with
# the same key, or Android refuses to install it over this one.
KEYSTORE = os.path.join(HERE, "diceanddamage.keystore")
KEY_ALIAS, KEY_PASS = "diceanddamage", "diceanddamage"

SCREEN_ORIENTATION_PORTRAIT = 1

# Declared by the stock shell, unused by this game: audio and sound are off in
# conf.lua, nothing vibrates, nothing talks to the network, nothing reads
# outside the save directory. Typing a preset name uses the on-screen keyboard,
# which needs no permission. The androidx DYNAMIC_RECEIVER permission stays,
# because androidx registers a receiver with it at startup.
DROP_PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.VIBRATE",
    "android.permission.BLUETOOTH",
    "android.permission.RECORD_AUDIO",
    "android.permission.WRITE_EXTERNAL_STORAGE",
]


def run(cmd, **kw):
    subprocess.run(cmd, check=True, **kw)


# ---------------------------------------------------------------- the shell

def fetch_shell():
    if os.path.exists(SHELL):
        return
    os.makedirs(BUILD, exist_ok=True)
    print("downloading the LÖVE for Android shell ...")
    run(["curl", "-sL", "--max-time", "600", "-o", SHELL, SHELL_URL])
    with zipfile.ZipFile(SHELL) as z:
        assert "lib/arm64-v8a/liblove.so" in z.namelist(), "not the embed shell"


# ---------------------------------------------------------------- the game

# Everything in game/ ships: the Lua, and the typeface the whole layout is
# measured in, with its licence. Without the .ttf the app would still run --
# ui.lua falls back to LOVE's built-in font -- so its absence has to be caught
# here, not noticed on a phone as slightly different spacing.
SHIPPED = (".lua", ".ttf", ".txt")


def pack_game():
    love = os.path.join(BUILD, "game.love")
    with zipfile.ZipFile(love, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(os.listdir(GAME)):
            if name.endswith(SHIPPED):
                # A fixed date, so the same sources always make the same file.
                info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                z.writestr(info, open(os.path.join(GAME, name), "rb").read())
    with zipfile.ZipFile(love) as z:
        names = z.namelist()
        for need in ("main.lua", "conf.lua", "hooks.lua", "icons.lua", "DejaVuSans.ttf"):
            assert need in names, need + " missing from game.love"
        # The shipped hooks must be the empty ones, never a test driver.
        hooks = z.read("hooks.lua").decode("utf-8")
        assert "function hooks.frame() end" in hooks, "hooks.lua is not the shipped no-op"
    return love


# ---------------------------------------------------------------- manifest

def patch_manifest(raw):
    m = axml.Axml(raw)
    p = m.pool

    changes = [
        ("org.love2d.android", APP_ID),
        ("org.love2d.android.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
         APP_ID + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"),
        ("org.love2d.android.androidx-startup", APP_ID + ".androidx-startup"),
        ("LÖVE for Android", APP_LABEL),
        ("11.5a", VERSION_NAME),
    ]
    for old, new in changes:
        hits = p.replace(old, new)
        assert hits, "manifest string not found: " + old
        print("  %-58s -> %s" % (old, new))

    # The shell declares what LÖVE might need; this game needs none of it.
    # Nothing here can fail to launch for want of a permission -- the code
    # checks at the point of use and takes the denied branch -- and a dice
    # roller listing microphone and Bluetooth in App Info is a bad look.
    gone = m.remove_elements("uses-permission", "name", set(DROP_PERMISSIONS))
    assert set(gone) == set(DROP_PERMISSIONS), \
        "expected to drop %s, dropped %s" % (DROP_PERMISSIONS, gone)
    for g in gone:
        print("  %-58s -> removed" % g)

    n = m.set_int_attr("activity", "screenOrientation",
                       SCREEN_ORIENTATION_PORTRAIT)
    assert n == 1, "expected exactly one screenOrientation, found %d" % n
    print("  %-58s -> portrait" % "screenOrientation")

    n = m.set_int_attr("manifest", "versionCode", VERSION_CODE)
    assert n == 1
    print("  %-58s -> %d" % ("versionCode", VERSION_CODE))

    out = m.serialize()

    # Read it straight back. A bad pool or a mis-sized typed value parses as
    # garbage rather than failing, and the first sign of that would be a phone
    # refusing to install -- so check the values, not just that it reparses.
    check = axml.Axml(out)
    assert check.pool.strings == p.strings, "round trip lost the string pool"
    assert APP_ID in check.pool.strings
    assert "org.love2d.android.GameActivity" in check.pool.strings, \
        "the activity class name must stay in the LÖVE package"
    assert check.get_attr("activity", "screenOrientation") == \
        [(axml.TYPE_INT_DEC, SCREEN_ORIENTATION_PORTRAIT)], "orientation not set"
    assert check.get_attr("manifest", "versionCode") == \
        [(axml.TYPE_INT_DEC, VERSION_CODE)], "versionCode not set"
    # The attribute after versionCode is the one an oversized write would eat.
    assert check.get_attr("manifest", "versionName") == \
        [(axml.TYPE_STRING, p.index(VERSION_NAME))], "versionName was trampled"

    left = set()
    for buf, elem, attrs in check.elements():
        if elem != "uses-permission":
            continue
        for _, a_name, off in attrs:
            raw = struct.unpack_from("<I", buf, off + 8)[0]
            if check.pool.strings[a_name] == "name" and raw != 0xFFFFFFFF:
                left.add(check.pool.strings[raw])
    assert not (left & set(DROP_PERMISSIONS)), "a permission survived: %s" % left
    assert any("DYNAMIC_RECEIVER" in s for s in left), \
        "the androidx receiver permission must stay"
    return out


# ---------------------------------------------------------------- assembly

def assemble(love_path, icons):
    unsigned = os.path.join(BUILD, "unsigned.apk")
    manifest = None

    with zipfile.ZipFile(SHELL) as src:
        manifest = patch_manifest(src.read("AndroidManifest.xml"))
        with zipfile.ZipFile(unsigned, "w") as dst:
            for info in src.infolist():
                name = info.filename
                if name.startswith("META-INF/") and name.rsplit(".", 1)[-1] \
                        in ("RSA", "SF", "DSA", "MF"):
                    continue                      # the shell's own signature
                if name == "AndroidManifest.xml":
                    data = manifest
                elif name in icons:
                    data = open(icons[name], "rb").read()
                else:
                    data = src.read(name)
                # resources.arsc must stay uncompressed and aligned from
                # Android 11 on, so every entry keeps the shell's own method.
                out = zipfile.ZipInfo(name, date_time=info.date_time)
                out.compress_type = info.compress_type
                out.external_attr = info.external_attr
                dst.writestr(out, data)

            game = zipfile.ZipInfo("assets/game.love",
                                   date_time=(2026, 1, 1, 0, 0, 0))
            game.compress_type = zipfile.ZIP_STORED   # already a deflated zip
            dst.writestr(game, open(love_path, "rb").read())
    return unsigned


def sign(unsigned):
    if not os.path.exists(KEYSTORE):
        print("generating a signing key ...")
        run(["keytool", "-genkeypair", "-v", "-keystore", KEYSTORE,
             "-alias", KEY_ALIAS, "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "10000", "-storepass", KEY_PASS, "-keypass", KEY_PASS,
             "-dname", "CN=Dice Roller, OU=Local, O=Local, C=PT"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    aligned = os.path.join(BUILD, "aligned.apk")
    if os.path.exists(aligned):
        os.remove(aligned)
    run(["zipalign", "-p", "-f", "4", unsigned, aligned])
    run(["apksigner", "sign", "--ks", KEYSTORE, "--ks-key-alias", KEY_ALIAS,
         "--ks-pass", "pass:" + KEY_PASS, "--key-pass", "pass:" + KEY_PASS,
         "--out", OUT, aligned])
    run(["apksigner", "verify", "--verbose", OUT])
    run(["zipalign", "-c", "-p", "-v", "4", OUT], stdout=subprocess.DEVNULL)


# ---------------------------------------------------------------- read back

def check(love_path):
    """Android's own parser is the authority on the manifest: signing and
    verifying say nothing about whether it parses."""
    badging = subprocess.run(["aapt", "dump", "badging", OUT], check=True,
                             capture_output=True, text=True).stdout
    want = [
        "package: name='%s' versionCode='%d' versionName='%s'" % (APP_ID, VERSION_CODE, VERSION_NAME),
        "application-label:'%s'" % APP_LABEL,
        "uses-implied-feature: name='android.hardware.screen.portrait'",
        "launchable-activity: name='org.love2d.android.GameActivity'",
    ]
    for w in want:
        assert w in badging, "aapt does not report: " + w
    perms = [l for l in badging.splitlines() if l.startswith("uses-permission:")]
    assert perms == ["uses-permission: name='%s.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'" % APP_ID], \
        "unexpected permissions: %s" % perms
    print("aapt reads: %s" % "; ".join(w.split(":", 1)[1].strip() for w in want[:2]))
    print("            portrait, one permission (the androidx receiver's)")

    with zipfile.ZipFile(OUT) as apk:
        embedded = apk.read("assets/game.love")
        assert embedded == open(love_path, "rb").read(), "assets/game.love differs from the packed game"
        assert apk.getinfo("resources.arsc").compress_type == zipfile.ZIP_STORED
        for path in icon.DENSITIES:
            assert apk.read(path)[:8] == b"\x89PNG\r\n\x1a\n", path
    with zipfile.ZipFile(love_path) as z:
        for name in z.namelist():
            assert z.read(name) == open(os.path.join(GAME, name), "rb").read(), name + " differs from game/"
    print("embedded game.love matches game/ file for file")


def main():
    os.makedirs(BUILD, exist_ok=True)
    fetch_shell()
    love_path = pack_game()
    print("packed %s (%d bytes)" % (os.path.basename(love_path),
                                    os.path.getsize(love_path)))

    _, files = icon.write(os.path.join(BUILD, "icons"))
    icons = {os.path.relpath(f, os.path.join(BUILD, "icons")): f for f in files}

    print("patching the manifest:")
    unsigned = assemble(love_path, icons)
    sign(unsigned)
    check(love_path)
    print("\n%s  (%.1f MB)" % (OUT, os.path.getsize(OUT) / 1e6))


if __name__ == "__main__":
    main()
