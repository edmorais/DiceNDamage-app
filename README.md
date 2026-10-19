# Dice & Damage - desktop & Android

**A damage calculator and dice roller for Dungeons & Dragons 5e and similar RPGs.**

Dice & Damage answers two questions at the table: *how likely is this attack
to land, and how much will it hurt?* Then it rolls the dice for you. 3D
dice are thrown onto a carved stone dais. The odds are exact, worked out from
the rules, not guessed from simulations.

You can keep a party of characters, each with their own saved attacks. Switching
from your fighter's greatsword to your rogue's sneak attack takes one click. You may save your settings to load on the web app!

You can sideload the Android app using the .apk from the Releases page!
You can also use the app on your computer if you have [LÖVE](https://love2d.org) installed.

Check also the web app at <https://github.com/edmorais/DiceNDamage-web>

Made with Claude Opus 5.5 and LÖVE/Lua.

---

## Contents

- [Installing](#installing)
- [The screen at a glance](#the-screen-at-a-glance)
- [The four tabs](#the-four-tabs)
- [Playing a turn](#playing-a-turn)
- [Attack presets](#attack-presets)
- [Your party](#your-party)
- [Saving, backing up and moving your party](#saving-backing-up-and-moving-your-party)
- [Colour schemes](#colour-schemes)
- [Touch, buttons and keys](#touch-buttons-and-keys)
- [The rules it follows](#the-rules-it-follows)
- [Questions and answers](#questions-and-answers)

---

## Installing

### On an Android phone or tablet

1. Copy `DiceAndDamage.apk` to your phone, or download it there.
2. Open it. Android may ask you to allow your file manager or browser to
   *install unknown apps*. Allow it for that app, then go back and open the
   file again.
3. Tap **Install**. The app appears as **Dice & Damage**, with a gold d20 on
   an orange burst.

**Updating from version 1.0?** Install the new file over the old one. Your
saved attacks are kept: the first time it opens, they become a character
called *My character*.

Dice & Damage needs no internet connection and asks for no permissions.

### On a computer

Install [LÖVE](https://love2d.org) 11.4 or 11.5. Then drag
`DiceAndDamage.love` onto the LÖVE application, or run it from a terminal:

    love DiceAndDamage.love

The window is shaped like a phone held upright. You can resize it.

### The first time you open it

You meet three example characters: **Brannoc** (a fighter), **Vex** (a rogue)
and **Sister Ilse** (a paladin). Use them to explore. Edit them, delete them,
or add your own when you are ready.

---

## The screen at a glance

From top to bottom:

- **The current character**: their badge, name and note. Tap the name to
  open the party.
- **The colour button**, at the top right, shows three dots of the current
  colour scheme. Tap it to change the scheme.
- **Four tabs**, shown as icons:

  | Icon | Tab |
  | --- | --- |
  | a calculator | **Calculator**: the odds |
  | a sword | **Attack**: roll to hit, or an ability check |
  | an impact burst | **Damage**: roll damage |
  | **%** | **Percent**: roll a d100 |

- **The tab itself**: its settings, and on the rolling tabs a tray where the
  dice land.
- **The roll buttons** at the bottom. Each one carries the icon of the tab
  where its result lands.

---

## The four tabs

The Calculator, Attack and Damage tabs all work on the **same attack**. If
you add a d6 on the Damage tab, it is there on the Calculator too. The
enemy's AC and the roll mode are also shared, so you only set them once.

### Calculator

The Calculator tells you what to expect from your attack before you roll.
Drag up and down to scroll it.

**The box at the top** shows the two numbers that matter most:

- **Chance to hit**: how often each attack lands against the enemy's AC.
  Under it, what you need on the d20, such as *needs 8+ on the d20*.
- **Average damage**: what you deal in a typical round, counting misses.

Under them, a bar splits each attack into **crits** (brightest), **hits** and
**misses**, with the crit and miss chances at either end.

- **One attack a round:** the middle of the line shows how much the damage
  varies from round to round (±), and the most you can possibly deal.
- **More than one attack:** it shows the chance that **at least one** of them
  lands.

**The chart** has two views. Choose one with the buttons above it.

- **Distribution** shows how likely each damage total is. The dashed line
  marks the average. **Cumulative** adds a curve that reads "this much damage
  *or more*", from 100% down to 0%, on the scale at the right.
- **Damage vs AC** shows your average damage against every AC from 5 to 30,
  with one line for each roll mode. Use it to see how much advantage is
  worth, or how fast your damage falls against heavily armoured enemies.

**Drag your finger across the chart** to read exact numbers.

- **On Distribution**, the line above the chart shows the chance of dealing
  exactly that total, and that total or more.
- **On Damage vs AC**, it shows the average at that AC for all three roll
  modes.

**The situation** is about the fight you are in:

- **Enemy AC**. The box next to it shows what you need on the d20, such as
  *8 or more*.
- **Roll mode**: Disadvantage, Normal or Advantage.

**Your attack** is what a preset saves:

| Setting | What it is | Range |
| --- | --- | --- |
| Attack bonus | What you add to the d20 to hit | −5 to +20 |
| Attacks per round | Extra Attack, two-weapon fighting and so on | 1 to 4 |
| Damage dice | One or more groups, such as `1d8` and `3d6` | up to 5 groups, 15 dice |
| Damage bonus | What you add to the damage dice | −10 to +50 |
| Crit range | The d20 rolls that score a critical hit | 20, 19–20 or 18–20 |

To change the dice:

- Tap a group's label, such as `1d8`, to cycle the die size: d4, d6, d8,
  d10, d12, d20.
- Use **−** and **+** to change how many dice the group has.
- **+ Add dice** adds another group, for sneak attack, a smite, hex and the
  like.
- **×** removes a group.

**Roll attack** at the bottom takes you to the Attack tab and rolls there.

### Attack

The Attack tab rolls a d20. Switch between the two kinds of roll at the top
of the tab.

**Attack roll** uses your attack bonus against the enemy's AC, in the current
roll mode. The tray's heading says what is being rolled, such as *d20 + 7 vs
AC 15*. After the roll, the tray tells you whether you **hit** or **missed**.
On a natural 20 it says **Critical hit**, and on a natural 1 **Critical
fail**.

With advantage or disadvantage, two d20s are thrown. The one that counts is
ringed, and the other fades.

Press **Damage** to go straight to the Damage tab and roll your damage. After
a critical hit the button turns into **Crit damage**, and your damage dice
are doubled automatically.

**Ability check** is for checks and saving throws. It has its own
**Modifier** and **Target DC**, kept apart from your attack, so a Dexterity
save never changes your weapon. Leave the DC at **Off** to just roll. With a
DC set, the tray tells you whether you pass or fail. The ability check has no
preset bar, because a check is not an attack.

### Damage

The Damage tab rolls your attack's damage dice and adds the damage bonus.
Damage never goes below 0.

- **Double the dice** is for critical hits. It is switched on for you when
  you come from a critical hit on the Attack tab, and stays on until you
  switch it off. Doubled rolls are marked **Critical damage**.
- If every die lands on its highest face, you see **Maximum damage**.

Press **New attack** to go back to the Attack tab and throw a new d20 for
your next attack.

### Percent

Percent rolls a d100: a number from 1 to 100. Use it for wild magic, random
tables and anything else your DM asks for in percent.

### Recent rolls

Each tray remembers your last six results, along its bottom edge. The newest
is on the right.

---

## Playing a turn

A typical turn with two attacks goes like this:

1. On the **Calculator**, set the **Enemy AC** if you know it, and the
   **roll mode**.
2. Press **Roll attack**. The app switches to the Attack tab and throws the
   d20.
3. If you hit, press **Damage**, or **Crit damage** after a critical hit.
   The app switches to the Damage tab and rolls your damage.
4. For your second attack, press **New attack** on the Damage tab. Then press
   **Damage** again if it hits.

Each attack is rolled on its own, so you always see what each swing did.

**Don't want to wait for the dice?** Tap the tray, or press the roll button
while it reads **Skip**. The dice land at once.

---

## Attack presets

A preset is a saved attack: the bonus, the dice, the damage bonus, the number
of attacks and the crit range. Each character can keep up to **eight**. The
enemy's AC and the roll mode are not part of a preset, because they belong to
the fight.

The **preset bar** sits at the top of the Calculator, the Attack roll and the
Damage tabs. It shows the loaded preset's name and a one-line summary, such
as "+7 to hit, 1d8 + 4, 2 attacks". Tap it to open the current character's
presets.

| To… | Do this |
| --- | --- |
| Load a preset | Tap its name. The list closes and the attack is ready. |
| Save the current attack | Tap **Save as new**, type a name, and tap **Save**. |
| Keep your changes to a loaded preset | Tap **Update** *(name)*. |
| Rename a preset | Tap the pencil ✎. |
| Delete a preset | Tap the **×**, then tap **Delete** to confirm. |

When you change something after loading a preset, the bar says **edited**,
and **Update** appears in the list. The preset itself only changes when you
tap **Update**.

While you type a name, the list moves to the top of the screen, so the
on-screen keyboard doesn't cover it. The first key you press replaces the
suggested name.

---

## Your party

Tap the character's name at the top of the screen to open **The party**.

Each character has:

- a **name**, up to 24 characters;
- a **dice colour**: Garnet, Emerald, Sapphire, Amethyst, Amber, Teal,
  Obsidian or Bone. It is shown on their badge;
- up to **eight attack presets**;
- their **own current attack**. When you switch back to a character, they are
  holding whatever you left them with.

Characters loaded from a file may also have a short **note**, such as their
class and level. It is shown under their name.

The enemy's AC, the roll mode and the ability check stay the same when you
switch characters, so the whole table can roll against the same monster.

**In the party list:**

- **Tap a character** to make them the active one. The list closes.
- **New character** adds one, up to twelve. Type a name and pick a dice
  colour. A new character starts with the attack you have on the table and
  no presets, so you can set it up and save it as their first preset.
- **The pencil ✎** changes a character's name or dice colour.
- **The ×** deletes a character. Tap **Delete** to confirm. If you delete the
  last one, a blank character called *Adventurer* takes its place.

Two characters can't share a name. If you use a name that is taken, the app
adds a number, as in "Vex (2)".

---

## Saving, backing up and moving your party

**Your party saves itself.** Every change is kept automatically: a moment
after you stop changing things, when you switch away from the app, and when
you close it.

On a phone, the party is kept inside the app. **Uninstalling the app deletes
it**, so make a backup first (see below).

### Making a backup, or sharing a character

The party list has two export buttons:

| Button | What you get |
| --- | --- |
| **Export** *(name)* | The current character, as a file called `name.json` |
| **Export party** | Everyone, as `dice-and-damage-party.json` |

Each export does two things:

- **It copies the file to the clipboard.** Paste it into a note, a message
  or an email to keep it safe or send it to a friend.
- **It saves the file in the app's `exports` folder.** On a computer you can
  find it there (see below). On a phone that folder is private to the app,
  so use the clipboard.

### Loading a file

There are two ways to load a character or party:

- **Copy** the file's text from a note, message or email, open the party and
  tap **Paste a file**.
- **On a computer**, drag the file onto the window.

The app reads:

- a character or party file exported from this app;
- a character or party file saved from the **Dice & Damage web app**;
- the `session.txt` file from Dice & Damage 1.0. Its presets become a new
  character.

Before anything changes, the app tells you what the file holds and asks what
to do:

| Button | What it does |
| --- | --- |
| **Add** | Adds the characters as new ones |
| **Replace** *(name)* | Swaps your character for the one in the file with the same name |
| **Replace same names** | For a party file: swaps each character that has a namesake in the file, and adds the rest |
| **Replace the party** | Swaps your whole party for the one in the file |
| **Cancel** | Changes nothing |

### Moving between your phone and the web app

The Dice & Damage web app uses the same files, so a party can go back and
forth:

- **From the phone to the web:** tap **Export party** on the phone. Send the
  text to yourself, open the party in the web app, and paste it in.
- **From the web to the phone:** in the web app, save your party or a
  character. Copy the file's text, and tap **Paste a file** on the phone.

Both apps have the same eleven colour schemes.

### Where the files are on a computer

| System | Folder |
| --- | --- |
| Windows | `%APPDATA%\LOVE\dnd-dice-and-damage\` |
| macOS | `~/Library/Application Support/LOVE/dnd-dice-and-damage/` |
| Linux | `~/.local/share/love/dnd-dice-and-damage/` |

Your party is kept there as `party.json`, and exports go to the `exports`
folder inside it. If `party.json` is ever damaged, the app keeps it as
`party.unreadable.json`, starts again from the examples, and tells you.

---

## Colour schemes

Tap the button with three coloured dots at the top right to change the
colour scheme. There are eleven:

| Scheme | Mood |
| --- | --- |
| Dragon's Hoard | Gold and ember on dark stone (the default) |
| Spellbook | Ink on parchment (light) |
| Arcane Neon | Electric blue and magenta |
| Necrotic Bloom | Sickly greens |
| Frostbite | Ice blue and amber |
| Ink & Bone | Black and white |
| Infernal | Fire and brimstone |
| Feywild | Twilight violet, pink and mint |
| Underdark | Fungal glow in the deep dark |
| Abyssal Tide | Deep sea green and coral |
| Celestial | Silver, gold and sky blue (light) |

---

## Touch, buttons and keys

**On a phone:**

- **Tap** a button to use it. Buttons act when you lift your finger, so if
  you slide off a button before you let go, nothing happens.
- **Hold** a **−** or **+** to change a value quickly.
- **Drag** up and down to scroll the Calculator, even when your finger starts
  on a button.
- **Drag across a chart** to read exact numbers.
- **The back button** cancels a name you are typing, then closes the open
  list. Otherwise it closes the app.
- **If the keyboard disappears** while you type a name, tap the name field to
  bring it back.

**On a computer**, click instead of tapping, and use the mouse wheel to
scroll. These keys also work:

| Key | Action |
| --- | --- |
| `1` `2` `3` `4` | Calculator, Attack, Damage, Percent |
| Space or Enter | Roll (or Skip while the dice are tumbling) |
| `r` | Roll a new attack, from any tab |
| `a` / `n` / `v` | Advantage / Normal / Disadvantage |
| `p` | Open or close the presets |
| `k` | Open or close the party |
| `[` / `]` | Previous / next character |
| `c` / Shift + `c` | Next / previous colour scheme |
| Ctrl + `v` | Paste a file, while the party is open |
| Enter / Esc | Save / cancel a name you are typing |
| Esc | Close the open list; otherwise close the app |

---

## The rules it follows

Dice & Damage follows the D&D 5e rules for attacks:

- A **natural 20** always hits and is a critical hit. With a wider crit range
  (19–20 or 18–20), those rolls are critical hits too.
- A **natural 1** always misses, whatever your bonus.
- Otherwise, you hit when the d20 plus your attack bonus is **equal to or
  higher than** the enemy's AC.
- **Advantage** keeps the higher of two d20s. **Disadvantage** keeps the
  lower.
- A **critical hit** doubles the damage **dice**, not the damage bonus.
- **Damage** is never below 0, even with a negative bonus.
- **Ability checks and saving throws** have no critical hits. A natural 20
  or a natural 1 is pointed out, but only the total against the DC decides.

The chances on the Calculator are worked out exactly from these rules, for
every possible roll of every die. Every face of every die in the trays is
equally likely.

---

## Questions and answers

**The dice landed on a number. Is that really the result?**
Yes. The result is decided the moment you press the button. The tumbling
faces are only for show, and the dice always come to rest on the real
result.

**Why doesn't Double the dice switch off by itself?**
So you can roll extra crit damage, such as a smite, after the first roll. It
is set for you each time you press Damage on the Attack tab: on after a
critical hit, off after a normal hit.

**I changed my attack and the preset bar says "edited". Did I lose the
preset?**
No. The preset is unchanged until you tap **Update** in the preset list. Tap
the preset's name to load it again as it was.

**Can I change a character's note?**
Not in the app. Notes come with the example characters and with files from
the web app, where you can edit them.

**Will I lose my party if I change phones?**
Only if you don't take it with you. Tap **Export party**, keep the text
somewhere safe, and tap **Paste a file** on the new phone.

**How do I start over?**
Delete the characters you don't want in the party list. If you delete the
last one, a blank character called *Adventurer* takes its place. To keep a
copy first, use **Export party**.

---

*For how the app is built and tested, see `DEVELOPERS.md`.*
