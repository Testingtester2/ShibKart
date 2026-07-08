# ShibKart

A Mario-Kart-style racer for the Boshi universe. Race the 10k Shiboshis (the chibi
rig, rendered through the shared **BoshiCore** engine — the same character art every
Boshi game uses), and **build your own tracks** in an in-game editor that saves and
loads them.

Built in **Godot 4.6** (GL Compatibility renderer).

## Launch

1. Open **Godot 4.6**.
2. Import / open `ShibKart/project.godot`.
3. Press **F5**.

The autoloads (`BoshiCore`, `BoshiBridge`, `GameState`) are declared in
`project.godot`, so it runs immediately — you do **not** have to enable the editor
plugin first. It runs with procedural placeholder art until you generate assets
(see below); the game loop, editor, and lap logic all work without any art.

## The runnable slice

Main menu → **Choose Boshi** (character select) → **Race** a track → finish the laps
→ results. Or **Track Editor** → draw a course → **Save** → **Test Drive**.

The **race** is a behind-the-kart 3D view (3D track receding to a horizon, karts and
the Boshi driver as billboard sprites — the classic 32-bit kart-racer look). The
**track editor** is top-down (as in the reference game), and the same saved track
loads straight into the 3D race. Karts render as low-poly 3D models tinted per racer,
with the chosen Boshi drawn on top via BoshiCore once its rig art is generated.

## Controls

Racing:

- **W / ↑** accelerate, **S / ↓** brake/reverse
- **A / ← , D / →** steer
- **Space / Shift** drift (hold through a corner, release for a mini-turbo boost)
- **Esc** back to menu

Track editor:

- **Left-click** empty space — add a waypoint (inserted into the loop sensibly)
- **Left-drag** a point — move it · **Right-click** a point — delete it
- **S** — set the selected waypoint as the start/finish line
- **Place Props** mode — left-click to drop the chosen prop, right-click to remove
- **Mouse wheel** zoom · **Middle-drag / arrow keys** pan
- **Save / Load / Test Drive** in the top toolbar

## Project layout

```
ShibKart/
├── project.godot            # Godot 4.6, GL Compatibility, autoloads, input map
├── icon.svg
├── scenes/                  # thin scene roots; each attaches one script
│   ├── boot.tscn  main_menu.tscn  character_select.tscn
│   ├── race.tscn  track_editor.tscn
├── scripts/
│   ├── game_state.gd        # autoload: chosen boshi + track, points BoshiCore at our art
│   ├── boot.gd  main_menu.gd  character_select.gd
│   ├── kart.gd              # shared kart controller (player + AI): accel/steer/drift/boost
│   ├── race.gd              # race loop: countdown, laps, positions, timing, HUD, results
│   ├── track.gd             # Track model: save/load JSON + geometry + checkpoints
│   ├── track_view.gd        # renders a Track (road ribbon, kerbs, start line, props)
│   └── track_editor.gd      # the in-game track editor
├── assets/
│   ├── karts/ tiles/ props/ ui/   # generated art lands here
│   └── tracks/                     # bundled .track.json courses
├── addons/boshicore/        # the shared BoshiCore engine (installed copy)
│   └── assets/                     # Boshi rig art (copied in by the asset script)
├── tools/                   # ComfyUI asset generation (see below)
└── docs/TRACK_FORMAT.md     # the save format, documented
```

## Boshi characters — via BoshiCore (not reinvented)

ShibKart consumes the shared addon and calls its public API:

```gdscript
var boshi = BoshiCore.spawn(traits, self)   # layered chibi compositor
boshi.play("run")
```

`GameState` points the compositor at ShibKart's copy of the rig art
(`res://addons/boshicore/assets/…`) and sets the chibi display height. Characters,
traits, animations and z-order all come from the canonical rig — ShibKart adds no
sprite/character logic of its own. See `NOTES_FOR_BOSHICORE.md` for two small
integration observations for the BoshiCore session.

## Assets — generate + auto-place

`tools/generate_shibkart_assets.py` makes every game asset with ComfyUI and drops
each into the right folder. It reuses your **proven** Qwen-Image-Edit workflow
(`gamedev/tools/spritegen/workflow.json`) exactly like `world_gen.py`/`fx_gen.py`:
it draws a crude **silhouette** for each asset, then lets ComfyUI polish it into a
finished sprite/texture. No LoRAs, nothing about your workflow is changed. Every
output passes a QA gate; tiles are made seamless; runs are resumable.

```bash
# 0. PROVE it offline first (no GPU): draws every silhouette + runs QA + checks the
#    manifest/sizes/folders. This is how you confirm it's perfect before generating:
python tools/generate_shibkart_assets.py --validate
python tools/generate_shibkart_assets.py --silhouettes   # also writes previews to assets/_silhouettes/

# 1. start ComfyUI (the same one you use for Boshi art) at 127.0.0.1:8188, then:
python tools/generate_shibkart_assets.py                 # everything, auto-placed
python tools/generate_shibkart_assets.py --only tiles    # one category
python tools/generate_shibkart_assets.py --only props/coin --force

# 2. bring the Boshi characters in (after the canonical rig is built once):
python tools/generate_shibkart_assets.py --boshis
```

The full asset list (51 assets: theme tiles, scenery billboards, props/items, karts,
UI, HUD icons, cup emblems) lives in `tools/asset_manifest.json`, derived from
`docs/GAME_DESIGN.md` (the full-game scope). Boshi character art is **not** generated
here — `--boshis` copies the canonical rig so ShibKart uses the same characters as the
other games.

## Tracks

The save format is plain JSON (`*.track.json`) — copy the file to share a track.
Full spec in [`docs/TRACK_FORMAT.md`](docs/TRACK_FORMAT.md). Two bundled tracks ship
in `assets/tracks/`.
