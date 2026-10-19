# Dice & Damage for LÖVE

The Damage Calculator and the Dice Roller as one app, in LÖVE 11 and Lua.
This is version 1.1: characters with their own presets, files shared with
the web app, a clearer Calculator, a new attack from the Damage tab, eleven
colour schemes and new typefaces.

To run it on a desktop:

    love game/                  # or
    love DiceAndDamage.love

The APK in this folder is still version 1.0. Version 1.1 hasn't been built
for Android yet (see [Android](#android)).

## What's new in 1.1

**Characters.** The name at the top of the screen is the character you are
playing, with a badge in their dice colour. Tap it to open **The party**:

- **Tap a character** to switch to them. Each character keeps their own
  attack presets (up to 8) and their own working attack, so switching brings
  back what that character was last holding. Enemy AC, roll mode and the
  ability check stay put: they belong to the fight, not to the character.
- **New character** starts from the attack on the table, with no presets.
  You name it and pick a dice colour. There can be up to 12 characters.
- **✎** renames a character or changes their colour. **×** deletes one; it
  asks first. The party is never left empty.
- On a desktop, **[** and **]** switch characters and **k** opens the party.

The first launch opens on the web app's three examples: Brannoc (fighter),
Vex (rogue) and Sister Ilse (paladin). If you used version 1.0, your presets
and settings become one character instead, called *My character*. The old
`session.txt` is left where it was.

**Files shared with the web app.** The party sheet reads and writes the web
app's own formats:

| Button | What it does |
| --- | --- |
| **Export** *name* | writes the character as `exports/<name>.json` and copies it to the clipboard |
| **Export party** | writes everyone as `exports/dice-and-damage-party.json` and copies it |
| **Paste a file** | reads a character file, a party file or a `session.txt` from the clipboard |
| drop a file on the window | the same, on a desktop |

Before anything changes, the sheet says what the file holds and asks: *Add*
it, *Replace* the character with the same name, or, for a party file,
*Replace the party*. Names stay unique; a second Vex comes in as *Vex (2)*.

On Android the exports folder is inside the app's private storage, so the
clipboard is the way across. Export on the phone, then paste into the web
app's party sheet, which takes pasted text; or copy a file's text on the web
side and tap **Paste a file** here. The app's own save file, `party.json`, is
a party file too, so the web app can load it as it is.

**The Calculator leads with two numbers.** The *damage to deal* setting is
gone. The box above the chart now shows the **chance to hit** with each
attack and the **average damage** per round, side by side, in large type.

- Under the chance to hit, it says what the d20 needs, for example *needs 8+
  on the d20*.
- Under them, one bar splits each attack into crit, hit and miss.
- With several attacks, the line under the bar gives the chance that at
  least one hits. With one attack, it gives the spread and the maximum.
- The old *Each attack* card is folded into this box.
- Next to Enemy AC, a box shows the same need as a number: *8 or more*.

The chart no longer draws a damage-to-deal line. Dragging across it still
reads exact odds.

**A new attack from the Damage tab.** The bottom of the Damage tab now has
**Roll damage** and, beside it, **New attack**. New attack switches back to
the Attack tab and throws a new d20, so a round goes attack, damage, attack,
damage on two buttons. The key r does the same from any tab.

**Eleven colour schemes.** The app's six are unchanged. The web app's five
are added, with the same colours and in the same order, so a scheme saved in
a file means the same thing on both:

- Infernal
- Feywild
- Underdark
- Abyssal Tide
- Celestial, a light scheme

The scheme button and c go forward; shift-c goes back.

**Typography.** The app now uses the web app's typefaces, so the two read as
one design:

| Face | Used for |
| --- | --- |
| Alegreya Sans | text, buttons, preset names |
| IM Fell English SC | the character's name and the section headings |
| Cinzel | the big numbers, the totals, the numbers on the dice, the verdicts |
| IBM Plex Mono | small spaced-out labels, chart axes, stepper values, dice expressions |

All four are under the SIL Open Font License, and their licences are in
`game/`. DejaVu Sans stays as the fallback for symbols the others lack
(✓ ✎ ⚔ −). Cards and pills are rounder, and labels above controls are small
capitals.

## Controls

| Touch / mouse | | Keys (desktop) | |
| --- | --- | --- | --- |
| tap | press a control | 1–4 | switch tabs |
| hold − / + | repeat | space, enter | roll |
| drag the chart | read exact odds | r | a new attack |
| drag elsewhere | scroll the Calculator | p | presets |
| wheel | scroll | k | the party |
| the name at the top | the party | [ / ] | previous / next character |
| drop a file | import it | n / a / v | normal, advantage, disadvantage |
| back button | close a sheet, otherwise quit | c / shift-c | next / previous scheme |
| | | ctrl-v | paste a file, in the party sheet |
| | | escape | close a sheet, otherwise quit |

## Saved settings

The party and the settings are saved to `party.json` in LÖVE's save folder
for the identity `dnd-dice-and-damage`. The save happens about 0.6 s after
the last change, again when the app loses focus (Android can stop an app
without quitting it), and again on quit.

- On Linux the folder is `~/.local/share/love/dnd-dice-and-damage/`.
- On Windows it is `%APPDATA%\LOVE\dnd-dice-and-damage\`.
- On Android it is inside the app's private storage, so uninstalling the app
  deletes it.

Exports go to `exports/` in the same folder.

`party.json` is the web app's party file with three more keys: the
situation, the interface settings and the current character. Every index in
it counts from 0, as the web app's do. The Lua code counts from 1, and
`store.lua` is the only place that converts. A `party.json` that can't be
read is kept as `party.unreadable.json`, and the app starts from the
examples.

## Files

    game/
      main.lua        frame loop, input, steppers, actions, the hand-offs, saving
      app.lua         the state every screen shares
      rules.lua       what an attack is, the limits, dice specs, UTF-8 names
      damage.lua      exact per-round damage distribution
      rolls.lua       d20 tests, damage, percentile
      store.lua       the party, and every file format shared with the web app
      json.lua        strict JSON in and out, written as the web app writes it
      session.lua     the first app's session.txt, read for imports and migration
      palettes.lua    the eleven colour schemes
      ui.lua          layout scale, typefaces, widgets, touch targets, the die renderer
      icons.lua       the four tab icons
      tray.lua        roll animation, dice layout, verdicts, recent totals
      calc.lua        the Calculator and the preset bar
      attack.lua      attack rolls and ability checks
      damagetab.lua   Damage and Percent
      sheet.lua       the presets sheet
      partysheet.lua  the party sheet: characters, export, import
      hooks.lua       the seam the test drivers replace; empty here
      conf.lua        window and identity
      *.ttf           the five typefaces, each with its licence
    test/             the tests below
    android/          the APK build: script, manifest patcher, icon, signing key
    screenshots/      renders at 1080 × 2400

`rules`, `damage`, `rolls`, `session`, `store` and `json` are plain Lua with
no LÖVE calls.

## Tests

All tests run headless on Linux, with LÖVE 11.5 under Xvfb.

    luajit test/logic.lua                 # 368 checks, no display needed
    luajit test/party.lua                 # 94 checks: the party and the file formats
    python3 test/render.py 1080x2400 out  # 33 screenshots, one per state
    python3 test/tapmap.py mouse 390x844  # real X pointer clicks on every control
    python3 test/tapmap.py touch 1080x2400
    python3 test/fuzz.py                  # 20,000 frames of random input
    python3 test/persist.py               # party.json, relaunch, migration, web files
    python3 test/mutants.py               # the tests catch known bugs

**Logic.** 368 checks, all passing, unchanged from 1.0. The expected values
come from the 5e rules and hand arithmetic, not from the code under test. The
Monte Carlo section plays 400,000 rounds for each of five attacks and rejects
a model with the AC off by one.

**Party and files.** 94 checks, all passing. The expected character file is
written out by hand from the web app's `store.js`: key order, two-space
indent, indexes from 0. Brannoc's file from this app must match it byte for
byte. The test also covers:

- the JSON reader refusing a dozen kinds of broken text;
- a hostile party file: names to clean, colours, crits and dice out of range,
  presets without dice, a character without a name, two names differing only
  in case;
- Add, Replace and Replace the party;
- the prototype's `session.txt` as an import and as a migration;
- the 12-character limit, unique names, and the party never empty;
- that switching characters switches the working attack.

**Tap map.** Every control on 14 screens is tapped on a freshly set-up
screen. The 4 new screens are the party, a new character, an import card and
a delete confirmation. Each control is checked three ways:

1. Its id is unique on its screen.
2. The tap lands on it and runs exactly its own action, once.
3. Your requests are walked through by taps, reading back what each tab
   shows.

The earlier requests are all still checked. New in 1.1:

- **New attack** on the Damage tab lands on Attack roll, with the right bonus
  and AC.
- Switching to Vex brings back Vex's attack and presets.
- A bonus changed on Vex stays on Vex: Brannoc still reads +7.
- The top bar shows the current character.
- A new character can be named and coloured, and starts with no presets and
  the attack on the table.
- Deleting a character takes two taps.
- **Export** puts Brannoc's file on the clipboard and in
  `exports/brannoc.json`, identical to the file the format test expects.
- **Paste** then **Replace** restores him.
- **Export party**, **Paste** and **Add** give *Brannoc (2)* and the other
  copies.
- **Replace the party** works.
- A foreign file is refused, and nothing changes.
- The scheme button goes through all eleven schemes and wraps round.

| Run | Checks | Failures |
| --- | --- | --- |
| mouse, 390 × 844, scale 1 | 912 | 0 |
| touch, 1080 × 2400, scale 2.77 | 916 | 0 |

**Fuzz.** 20,000 frames of random taps, holds, drags, keys, typing, and now
also party actions. When the party sheet is open, the clipboard is often
filled before **Paste**, with one of these:

- the app's own files;
- the web app's files;
- the prototype's `session.txt`;
- a file cut short at a random point;
- a party of 15 clones;
- a character with a 60-letter name and 13 presets;
- control characters.

After every frame the fuzzer checks everything it did in 1.0. It also
checks that:

- the party has 1 to 12 characters, with names unique ignoring case and clean;
- every character's presets and attack are inside the limits;
- the working attack lives on the character, never on the state;
- the keyboard is up exactly while a name is being typed in either sheet;
- `party.json` survives its own save and load exactly.

Every New attack is checked to land on the Attack tab with the right bonus
and AC. The final run held every invariant. It reached:

- 104 new attacks from the Damage tab;
- 288 character switches;
- 63 imports applied;
- a party of 12, the limit;
- 77 Calculator → Attack and 51 Attack → Damage hand-offs, 16 after a crit.

**Persistence.** 21 checks, all passing:

- The autosave writes `party.json` in the web app's format. That includes a
  preset saved on the second character with a UTF-8 name.
- A change made just before quitting survives the relaunch.
- A `party.json` cut short is kept as `party.unreadable.json`, and the app
  says so.
- The first app's `session.txt` becomes *My character*, with every preset,
  the working attack and the settings, and the file is kept.
- A party file in the web app's format, written out by hand, loads.

**Mutants.** Known bugs are put back into scratch copies of the game, one at
a time. The test that should catch each one must fail. All 14 were caught,
including the three added for 1.1:

| Bug put back | Result |
| --- | --- |
| no division by the layout scale (touch) | 455 failures |
| SDL's `istouch` mouse copies not ignored (touch) | 274 failures |
| the prototype's shared `chart` id | 16 failures, starting with the duplicate id |
| a crit that doesn't double the damage | 2 failures |
| held steppers that never repeat | 1 failure |
| no lost-touch watchdog | 2 failures |
| the Damage hand-off editing the dice | 3 failures |
| the Lua slip in the touch handler | 468 failures |
| **New attack re-rolling the damage instead** | 2 failures |
| **every character sharing one working attack** | 2 failures |
| **imports skipping the unique-name rule** | fuzz, frame 261 |
| closing the sheet leaves a name half-typed | fuzz, frame 483 |
| no name-length limit | fuzz, frame 138 |
| malformed bytes reaching the name | fuzz, frame 132: LÖVE's text drawing stops |

## Android

**For 1.1:** the build script is ready but hasn't been run. Its version is
now 1.1 (versionCode 2), so the build will install over 1.0. It already packs
every `.ttf` and `.txt` in `game/`, so the new typefaces and their licences go
in. The new fonts add about 1.4 MB.

On the first launch of 1.1, the 1.0 app's `session.txt` becomes *My
character*. The tests check that on the desktop; it hasn't been tried on a
phone.

`DiceAndDamage.apk` in this folder is version 1.0 (versionCode 1). It is 8.1 MB, built for
arm64-v8a and armeabi-v7a, with minSdk 16 and targetSdk 34, and locked to
portrait. Its application id is `com.dndtools.diceanddamage` and it has its
own launcher icon: the gold d20 in front of the crit-coloured impact burst. So
it installs next to the Dice Roller and the Damage Calculator rather than over
them. To rebuild it:

    python3 android/build_apk.py

The script is the Dice Roller's, with this app's id, label, icon and key. It
wraps the game in the official LÖVE 11.5 for Android **embed** shell, which it
downloads from the love2d/love-android release. Then it rewrites the binary
manifest with `android/axml.py`, replaces the launcher icons, and aligns and
signs the APK. It needs `zipalign`, `apksigner`, `aapt`, a JDK for `keytool`,
and Pillow.

| | from | to |
| --- | --- | --- |
| application id | `org.love2d.android` | `com.dndtools.diceanddamage` |
| receiver permission | `org.love2d.android.DYNAMIC_…` | `com.dndtools.diceanddamage.DYNAMIC_…` |
| provider authority | `org.love2d.android.androidx-startup` | `com.dndtools.diceanddamage.androidx-startup` |
| label | LÖVE for Android | Dice & Damage |
| orientation | landscape | portrait |
| permissions | INTERNET, VIBRATE, BLUETOOTH, RECORD_AUDIO, WRITE_EXTERNAL_STORAGE | removed |

Two things are new since the Dice Roller build:

- **The typeface ships.** The old script packed only `.lua` files, which
  would have left out `DejaVuSans.ttf`. The app would still have run, because
  `ui.lua` falls back to LÖVE's built-in font, just with slightly different
  spacing. So the script now packs everything in `game/` and fails if the
  typeface is missing. It also fails if `hooks.lua` isn't the empty shipped
  one, so a test driver can never end up in the APK.
- **Android's tools check the result.** Before, I checked it by hand. Now the
  script fails unless `aapt dump badging` reports:
  - the id, version and label;
  - portrait;
  - the GameActivity launcher;
  - exactly one permission, the androidx receiver's.

  It also fails unless `assets/game.love` matches `game/` file for file.

The signing key is `android/diceanddamage.keystore`, with the password
`diceanddamage`. It is a local key for sideloading, not for a store. Keep it:
a later build must be signed with the same key to install over this one.

**Checked:**

- `apksigner verify` passes the v1, v2 and v3 schemes.
- `zipalign -c -p 4` passes.
- `aapt dump xmltree` shows the new id on the package, the receiver
  permission and the provider authority.
- The activity class is still `org.love2d.android.GameActivity`.
- `assets/game.love`, taken out of the APK, runs under desktop LÖVE.

## What was and wasn't verified

**Verified.** Everything in Tests ran on the final 1.1 game code: LÖVE 11.5 on
Linux, with software OpenGL under Xvfb. I looked at the 33 screenshots:

- every screen in the default scheme;
- the party sheet, a new character, and an import card;
- each of the five new schemes on a different tab, including the light
  Celestial.

**Not verified:**

- **Version 1.1 on a phone.** No APK was built, as you asked, so nothing new
  ran on Android: not the clipboard, the keyboard for character names, or the
  migration from 1.0.
- **The web app reading this app's files.** The file formats were checked
  against the web app's own code and a character file written out by hand
  from it. Both directions were tested here, but no file went through the web
  app itself.
- **What 1.0 left unverified still applies.** No real phone was used for
  touch, high-density text wasn't rendered, and phone speed wasn't measured.
  The Calculator's worst case was about 40 ms with LuaJIT's compiler off.
- **Dropping a file on the window.** It uses LÖVE's `filedropped`. The tests
  cover the same import path through Paste, but no file was actually dropped,
  since Xvfb has no drag and drop.

## Findings in 1.1

**The autosave encoded the whole party every frame.** In 1.0 the session was
a few lines. A party of twelve characters with eight presets each is a JSON
file, and encoding it 60 times a second just to see whether anything had
changed would cost a phone real time. The app now checks four times a second.

**IM Fell English SC has oldstyle figures.** It is the display face for
names and headings, and in the verdict banners *Hits AC 15* set the 15 small,
below the capitals. The banners moved to Cinzel, whose figures line up with
its capitals. Alegreya Sans's figures are lining, which I checked before using
it for text.

**The new faces lack symbols the app draws.** ✓, ✎, ⚔ and − are not in all
of them. Every face now falls back to DejaVu Sans, so those symbols still
render.

**The tests assumed six schemes and one kind of sheet.** The scheme-cycling
check wrapped after six taps. The tap map found modal sheets by the presets
sheet's own id. So both failed as soon as the party sheet and the new schemes
arrived, which is correct. They now count eleven schemes, and they recognise
either sheet.

## Findings during the 1.0 port

**One Lua slip would have broken every touch.**
`onPress(ui.toDesign(x, y), id)` looks right, but Lua keeps only the first
value of a call that isn't last in an argument list. The finger's id would
have arrived as the y coordinate. I caught it on review before any test ran.
The touch test now fails 332 ways if it's put back.

**The click test trusted the attack it was checking.** It counted the dice
the hand-off should roll from the current attack. So a hand-off that quietly
edited the attack also passed. Mutation testing found this. The test now
counts from the preset itself: a Longsword crit is two d8 plus 4, and the
dice rows must still read 1d8.

**The fuzzer never typed a long name.** Names are committed after a few
characters, so dropping the 24-character limit went unnoticed. Real keyboards
and pasting deliver whole phrases at once, so the fuzzer now does too, and
the limit is checked.

**Malformed UTF-8 crashes LÖVE's text drawing.** It stops with *UTF-8 decoding
error*. Text from the keyboard is decoded strictly, character by character, so
bad bytes never reach a name. A mutant that let them through crashed within 64
frames of fuzzing.

**The damage icon first looked like a compass.** An even eight-pointed star
read as a compass rose or a "favourite". It is now eleven uneven spikes at
slightly uneven angles, which reads as a hit.
