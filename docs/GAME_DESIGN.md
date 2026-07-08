# ShibKart — Game Design Document (full scope)

A Boshi-universe kart racer in the spirit of classic 32-bit kart games (Crash Team
Racing / Diddy Kong Racing / Sonic R) and the reference *Mythic Kart Maker*: 3D
tracks, pre-rendered billboard characters, vehicular items, and a **build-your-own
track editor with save / load / share**. Characters are the 10k Shiboshis, rendered
through the shared **BoshiCore** rig so ShibKart uses the exact same art as every
other Boshi game.

This document is the source of truth for scope. The asset list (`ASSET_SPEC.md`) and
the generator (`tools/generate_shibkart_assets.py`) are derived from it.

---

## 1. Pillars

1. **Race the Boshies.** Every racer is a Shiboshi (chibi rig via BoshiCore).
2. **Build your world.** A first-class track editor: place a course, save it, load
   it, race it, share the file. (This is the headline feature of the reference game.)
3. **32-bit kart feel.** Behind-the-kart 3D, billboard sprites, drift-boost, items,
   punchy arcade handling.
4. **One shared engine.** No forked character/sprite logic — BoshiCore drives all
   characters; the same rig art appears here and in the other games.

---

## 2. Game modes

| Mode | Description | Content used |
|------|-------------|--------------|
| **Grand Prix** | Cups of 4 races; points per finish (15/12/10/8/7/6/5/4…); cup winner = most points. 3 cups at launch: **Shiba Cup**, **Bone Cup**, **Moon Cup**. | 12 tracks, standings, cup emblems |
| **Time Trial** | Solo vs the clock; ghost of your best lap; per-track leaderboard (local). | 1 track, ghost, splits |
| **VS Race** | Single quick race, pick track + laps + CPU count + difficulty. | any track |
| **Battle** | Arena mode: no laps, pop other karts with items; last kart / most KOs. | 2 arenas |
| **Track Editor** | Build, save, load, and test-drive your own tracks. Shareable `.track.json`. | editor, all tile themes |
| **Custom Cup** | Assemble your own 4-track cup from bundled + user tracks. | any tracks |

MVP order: VS Race + Editor (done) → Items → Grand Prix (cups) → Time Trial ghost →
Battle.

---

## 3. Racing systems

**Handling.** Accelerate / brake / steer / **drift** (hold through a corner to charge
a mini-turbo, release for a boost). Off-road slows you. Speed classes: 50cc / 100cc /
150cc scale top speed and CPU skill.

**Items (Mario-Kart-style).** Drive through an **item box** to roll a random item,
weighted by race position (back of the pack gets stronger items — rubber-banding):

| Item | Effect |
|------|--------|
| **Boost Bone** | instant speed boost (the "mushroom") |
| **Triple Bones** | three, used in sequence |
| **Shell (Kibble)** | homing projectile that spins out the kart ahead |
| **Banana Peel** | drop behind you; contact = spin-out |
| **Oil Slick** | drop a slick; contact = slide |
| **Shield Bubble** | blocks one hit for a few seconds |
| **Lightning (Moon Flash)** | shrinks + slows everyone ahead briefly |
| **Ghost** | brief intangibility + steal an item |

Item state per kart: current item, active effects (boost/shield/spinout timers).
Projectiles are simple homing/ballistic Node3D actors with collision radius.

**Hazards & pickups on track.** boost pads, coins (small speed + score), item boxes,
bananas/oil (from items or track props), jump ramps, speed strips.

**Race loop.** Countdown → laps (checkpoints from waypoints) → positions (progress
score) → finish order → results → (in GP) points + next race.

---

## 4. Characters & karts

**Characters** = Boshies from the roster (BoshiCore). Launch roster of 8 named
Boshies (extensible to any of the 10k via traits / wallet). Each has light **stat
weights**: Speed / Acceleration / Handling / Weight (kart-racer archetypes —
lightweight = nimble low-top-speed, heavy = high-top-speed low-accel).

**Karts** = a chosen chassis with its own stat curve, stacking with the character.
Launch: 4 chassis (Standard, Speedster, Drifter, Heavy). Rendered as a low-poly 3D
kart tinted to the racer's colour, with the Boshi as a billboard driver.

Character-select → kart-select → race. Stats shown as bars.

---

## 5. Tracks & themes

Tracks are authored top-down in the editor (centerline waypoints + width + props +
laps) and raced in 3D. **Themes** re-skin the ground/road/scenery of any track:

| Theme | Palette / scenery |
|-------|-------------------|
| **Grass Speedway** | green fields, trees, fences, hay bales |
| **Shibarium City** | neon night, buildings, signs, guardrails |
| **Bone Desert** | sand/dirt, cacti, rock arches, bones |
| **Moon Base** | low-grav sci-fi, panels, stars, craters |
| **Cherry Grove** | pink blossom, lanterns, water |

Each theme = a texture set (road/ground/kerb) + a scenery billboard set. 12 launch
tracks distributed across themes and cups. Track file stores an optional `theme` key
(defaults to Grass) — additive, backward compatible with the v1 format.

---

## 6. Progression & persistence

- **Save file** (`user://shibkart_save.json`): unlocked cups/karts/characters, GP
  results, Time-Trial best times + ghosts, options.
- **Unlocks**: win a cup → unlock the next cup + a kart/character.
- **Track library**: bundled tracks + user tracks (`user://tracks/`), shareable files.

---

## 7. UI / screens

Title → Main Menu → (Mode) → Character Select → Kart Select → Track/Cup Select →
Race → Results → (GP: standings → next). Plus: Editor, Options (volume, speed class,
controls), Garage (view unlocks).

HUD: lap counter, position, timer, speedometer, **item slot**, mini-map, lap-split
popups, "GO!/LAP/FINISH" banners, boost/drift flash.

---

## 8. Audio (hooks; assets later)

- Music: menu theme, per-theme race tracks, results jingle.
- SFX: engine loop (pitch by speed), drift, boost, item pickup/use, shell hit, coin,
  countdown beeps, finish.
- An `AudioBank` autoload maps names → streams; safe no-ops if a stream is missing.

---

## 9. Asset implications (feeds ASSET_SPEC.md)

The scope above requires: per-theme **ground/road/kerb textures** (tileable);
per-theme **scenery billboards** (trees, buildings, cacti, panels, blossom, fences,
rocks, signs); **prop/item billboards** (item box, boost pad, coin, banana, oil,
shell, bone, shield, ramp); **HUD/UI** (logo, buttons, panels, item icons, position
badges, cup emblems, speed/lap/coin icons, minimap frame); **kart chassis decals**;
and **character portrait cards** for select (portraits can also be rendered live from
the BoshiCore rig). Characters themselves are NOT generated here — BoshiCore owns them.

---

## 10. Build roadmap

1. **(done)** Race core, drift/boost, AI, laps, HUD, editor + save/load, character
   select, 3D behind-kart view, scenery/banners.
2. **Art pipeline** (flawless, validated) + full asset spec — *current focus*.
3. **Textures & billboards wired** into the 3D race (themes).
4. **Items & item boxes** (the combat layer).
5. **Grand Prix cups** + standings + save/unlocks.
6. **Kart select** + stats; **Time Trial** + ghost; **Battle** arenas.
7. **Audio bank**, options, garage, polish.
