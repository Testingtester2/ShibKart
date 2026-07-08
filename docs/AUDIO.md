# ShibKart audio

Two buses under Master — **Music** and **SFX** — created at runtime by
`AudioManager` (autoload). Volume/mute are on the **Options** panel (main menu).
Everything is graceful: any missing file is simply silent, never a crash.

## Music — you (maz) provide one looping mp3 per map

Drop files here:

```
assets/audio/music/<track_id>.mp3
```

The game loads `<track_id>.mp3` for the map being raced, loops it seamlessly, and
crossfades on race start / return to menu. If a track's own mp3 is missing it falls
back to a **per-biome** file `<theme>.mp3`, then to silence.

### Exact filenames to drop (one per current map):

| Map (in-game name)       | track_id         | drop this file                               |
|--------------------------|------------------|----------------------------------------------|
| Boshi Speedway           | `boshi_speedway` | `assets/audio/music/boshi_speedway.mp3`      |
| Cherry Blossom Run       | `cherry_run`     | `assets/audio/music/cherry_run.mp3`          |
| Shibarium City Loop      | `shibarium_loop` | `assets/audio/music/shibarium_loop.mp3`      |
| Bonebark Dunes           | `bone_dunes`     | `assets/audio/music/bone_dunes.mp3`          |
| Luna Circuit             | `luna_circuit`   | `assets/audio/music/luna_circuit.mp3`        |
| Frostpaw Ridge           | `frost_ridge`    | `assets/audio/music/frost_ridge.mp3`         |
| Ember Valley             | `ember_valley`   | `assets/audio/music/ember_valley.mp3`        |
| Sunset Bay               | `sunset_bay`     | `assets/audio/music/sunset_bay.mp3`          |
| **Main menu**            | `menu`           | `assets/audio/music/menu.mp3`                |

Custom tracks made in the editor use their saved slug as `track_id`; give them a
matching mp3 or they'll use the biome fallback / silence.

**Optional per-biome fallbacks** (used if a map's own file is absent): `grass.mp3`,
`cherry.mp3`, `city.mp3`, `desert.mp3`, `moon.mp3`, `snow.mp3`, `volcano.mp3`,
`beach.mp3`.

So the minimum to fully score the game: **9 mp3s** (8 maps + menu). Or provide the
**8 biome** files instead and every map is covered by fallback.

> mp3 loops: Godot loops the whole file. For a truly seamless bed, export the loop
> so the end meets the start cleanly (no trailing silence).

## SFX — generated for you (no AI needed)

Run once (already run for you):

```
python tools/generate_shibkart_audio.py
```

It writes 20 procedural WAVs to `assets/audio/sfx/`. Replace any file with your own
(or AI-generated) sound and the game picks it up — it looks for `<name>.wav`, then
`.ogg`, then `.mp3`.

Generated SFX: `beep`, `go`, `lap`, `finish`, `coin`, `boost`, `turbo`, `drift`,
`bump`, `item_pickup`, `shell`, `banana`, `oil`, `shield`, `lightning`, `ghost`,
`click`, `select`, `engine` (looping, pitch-scales to speed), `offroad` (looping).

## What still needs providing vs. what's covered

- **You provide:** the map music mp3s (table above). That's it for a fully-scored build.
- **Covered by the SFX script:** every sound effect (replaceable).
- **No new visual assets required** for audio. (Track textures/scenery are already
  handled by `generate_shibkart_assets.py`; scenery/road geometry is procedural.)
