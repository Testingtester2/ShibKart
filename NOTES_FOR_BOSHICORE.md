# Integration notes for the BoshiCore session

ShibKart consumes the shared addon (installed copy at `ShibKart/addons/boshicore/`).
It uses the **layered** `BoshiCore.spawn()` path. One BLOCKER had to be fixed in the
installed copy to make the addon compile in Godot 4.6 (item 0); please fold it back
into the canon. Two further observations follow.

## 0. BLOCKER — `boshi_compositor.gd` does not compile in Godot 4.6 (FIXED locally)

`boshi_compositor.gd` initialized two consts directly from the `BoshiRig` global
class name:

```gdscript
const RIG := BoshiRig.RIG
const SLOT_ORDER := BoshiRig.SLOT_ORDER
```

Godot 4.6 resolves global `class_name`s **after** the const-folding pass, so a `const`
initialized from `BoshiRig.RIG` fails with a parse error. That cascades: `boshi_core.gd`
(which `preload`s the compositor) reports *"Failed to compile depended scripts"*, the
`BoshiCore` autoload becomes `<null>`, the global-class cache is left incomplete, and
unrelated game scripts (e.g. `character_select.gd`) then also report a parse error.

**Fix applied in ShibKart's installed copy** (please apply in
`_boshicore_canon/addons/boshicore/boshi_compositor.gd` too):

```gdscript
const RIG := preload("res://addons/boshicore/boshi_rig.gd").RIG
const SLOT_ORDER := preload("res://addons/boshicore/boshi_rig.gd").SLOT_ORDER
```

`preload(...).CONST` is a valid constant expression, so this compiles cleanly and keeps
the single-source-of-truth semantics. Runtime uses of `BoshiRig` (e.g.
`BoshiRig.frame_boxes(...)`) are fine and unchanged — only the two `const` initializers
needed it. This is the one place ShibKart had to touch the installed addon; it is a
straight bug-fix, not a behavioural fork.

## 0b. Rig gap — no directional / turn frames for billboard racers

ShibKart's pseudo-3D racers are camera-facing billboards fed by BoshiCore. The rig
exposes `idle / walk / run` only. For a Mario-Kart look the driver should show
**left / right turn (lean) frames** (and ideally 3–5 yaw angles) so the billboard
reads correctly as the kart turns toward/away from camera. Right now the billboard
always faces front, which is acceptable but flat.

Suggested canon addition: an optional `turn_left` / `turn_right` (or a small
angle-indexed set) in the rig spec + generator, exposed via the compositor so games
can pick a frame by steer/heading-vs-camera angle. ShibKart will consume it if added;
until then it uses the front-facing billboard. Not a blocker.

## Further observations (not fixed here)

## 1. `generate_all.py` GAME_DESTS doesn't include ShibKart

`_boshicore_canon/generate_all.py` auto-copies the rig into `shadowcat` and
`shibtown` only:

```python
GAME_DESTS = {
    "shadowcat": ROOT / "apps" / "shadowcat-survivors" / "addons" / "boshicore" / "assets",
    "shibtown":  AIVIDS / "ShibTown" / "game" / "addons" / "boshicore" / "assets",
}
```

**Suggested addition** (so the canonical script can place art into ShibKart too):

```python
    "shibkart":  AIVIDS / "ShibKart" / "addons" / "boshicore" / "assets",
```

and add `"shibkart"` to the `--games both` list. **Workaround in the meantime:**
ShibKart's own `tools/generate_shibkart_assets.py --boshis` copies the canonical
`gamedev/assets/maz_*.png` + `traits/` into `ShibKart/addons/boshicore/assets/`
itself, so nothing in the shared repo needs to change for ShibKart to work.

## 2. Baked-mode timing in `boshi_compositor.gd` (only affects `spawn_baked`)

`_bake_one_frame()` does `await RenderingServer.frame_post_draw`, so `_build_baked()`
and therefore `build()` become async when baking. But `boshi_core.gd`'s `_spawn()`
and `bake_frames()` call `comp.build(...)` **without awaiting**, then immediately read
`comp.get_baked_frames()`. The baked `SpriteFrames` can be empty at that moment
because the SubViewport snapshots haven't completed.

Impact on ShibKart: **none today** — ShibKart uses layered `spawn()` (a handful of
karts on screen), never `spawn_baked()`. But a kart racer with a full 8-boshi grid or
future crowd scenes is exactly the case that would want baked mode, so it'd be good
for the shared module to make `bake_frames()` awaitable (or have the compositor emit a
`baked_ready` signal) before ShibKart adopts it for grids.

Neither item blocks ShibKart's runnable slice.
