# BoshiCore Canonical Rig Spec — v1 (source of truth)

**Status:** authoritative. Both game sessions (`apps/shadowcat-survivors`, `ShibTown/game`)
and every ComfyUI generation script MUST conform trait/base art to this spec.
**Scope:** the Boshi/Maz playable-character rig only (not enemies, FX, tiles).
**Location:** this folder (`gamedev/_boshicore_canon/`) is an **untracked scratch proposal**
so it does not disturb the two active sessions. Promote to `gamedev/BoshiCore/SPEC/`
(or `packages/boshy-core/`) once reviewed.

---

## 0. Why this document exists (the failure it fixes)

Stacking degraded because **there is no single enforced canvas**. Art for the same
character currently exists on at least **four incompatible rigs**, and trait overlays
were authored against a *mixture* of them. The runtime compositor blends the *same
`Rect2i`* from the base sheet and from every trait sheet, so any layer authored on a
different canvas lands offset/scaled wrong — which is exactly the drift you see.

Measured rigs found on disk (all for the same character):

| Rig / source | idle | walk | run | frame layout |
|---|---|---|---|---|
| **Canonical** `assets/maz_*.png`, `boshi_sheets/*` | 1280×426 / 6f | 1280×640 / 8f | 1568×784 / 6f | compact horizontal strip ✅ |
| shadowcat game copy `apps/shadowcat-survivors/assets/maz_*.png` | 1098×426 / 6f | 1376×640 / 8f | 1836×784 / 6f | strip, different widths ⚠️ |
| ShibTown game copy `ShibTown/game/assets/player/boshi_*.png` | 1768×584 / 6f | 1267×720 / 8f | 1448×720 / 6f | strip, different H+W ⚠️ |
| **Raw ComfyUI dumps** `BoshiCore/`, `Newgeneratedassets/` | 1024×1024 / 6f | 1024×1024 / 8f | 1024×1024 / 6f | **exploded 1-PNG-per-frame** ❌ |

`assets/traits/` overlays are a mix of `1280×426`, `1280×640`, `1568×784` (canonical) **and**
`1768×584`, `1448×720` (ShibTown rig) **and** `1320×380` (neither). Overlays from one rig
stacked on a base from another = the degradation.

**Root cause, one sentence:** a divergent generation path was added that writes raw
per-frame `1024×1024` ComfyUI `SaveImage` outputs (the `_00001_` suffix, 1,643 files /
670 MB in `BoshiCore/`) straight to disk — bypassing `run.py`'s in-register
slice→transform→bg_remove→normalize→pack — so frames are exploded, on a canvas unrelated
to any game rig, with per-frame float in scale/position; registration and pivots are
destroyed and multi-layer stacking cannot line up.

**The one rule that makes stacking work:** *base and every trait overlay for a given
animation share one identical authoring canvas and 1:1 frame boxes. Per-game display
scaling happens AFTER compositing, never before, and never per-layer.*

---

## 1. Canonical authoring canvas (fixed)

All base and trait art is authored/generated at exactly these dimensions. This is the
`gamedev/assets/maz_*.png` rig (already correct in `boshi_sheets/`), chosen because
`run.py` transform-mode already produces it and `BOSHI_PIPELINE.md` documents it.

| anim | required | canvas (W×H) | frames | frame width | fps | pivot (per frame) |
|------|----------|--------------|--------|-------------|-----|-------------------|
| `idle` | **yes** | **1280 × 426** | **6** | 213/214 px* | 9  | feet: (frame_center_x, 425) |
| `walk` | **yes** | **1280 × 640** | **8** | 160 px | 14 | feet: (frame_center_x, 639) |
| `run`  | **yes** | **1568 × 784** | **6** | 261/262 px* | 16 | feet: (frame_center_x, 783) |
| `jump` | optional | 1280 × 640 | 4 | 320 px | 10 | feet: (frame_center_x, 639) |

\* Non-integer frame widths (1280/6, 1568/6) are tiled with **rounded fractional cuts**
so the strip is byte-for-byte the source size and every column is covered exactly once.
Use the shared helper — do not hand-slice:

```python
def frame_boxes(width, n):
    return [(round(i*width/n), round((i+1)*width/n)) for i in range(n)]
```

Frame counts (`idle 6 / walk 8 / run 6`) are **hard-locked** — they must match
`scripts/player.gd` / `boshi_rig.gd` ANIMS. Changing a count is a breaking rig change and
requires a spec version bump.

### Pivot / anchor
- **Horizontal:** character is centered in its frame box (`x = frame_center`). No per-frame
  left/right wobble.
- **Vertical:** feet stand on a **common baseline** = the bottom row of the canvas
  (`y = H-1`). Natural stride bob is allowed *within* a frame but the baseline is shared,
  so `normalize_frames()` in `run.py` must run on every animation.
- The Godot AnimatedSprite2D node is placed so this feet baseline is the node origin
  (`offset.y = -H` for a top-left texture, or center the region and offset by half).

---

## 2. Trait slots and z-order (fixed)

Composite order, **back-most first** (source: `_TRAIT_ORDER` in
`legacy/godot-prototype/scripts/player.gd` + `assets/traits/README.md`):

```
0 Fur        (palette / base body tint — NOT a sheet; hue-shift the base)
1 Body       (base naked-boshi sheet — the bottom drawable layer)
2 Clothing   (sheet)
3 Mouth      (sheet)
4 Eyes       (sheet)
5 Headwear   (sheet)
6 Accessory  (sheet)   ← drawn last / on top
```

- `Fur` and `Body` are the base: fur is a **palette hue-shift** applied to the naked base,
  not an overlay sheet (do NOT generate fur sheets). Everything ≥ index 2 is a trait
  overlay sheet.
- Higher index = drawn later = visually on top.
- Empty/absent slot = skip (nothing drawn). A `"none"` value resolves to no sheet.
- The Godot compositor MUST create one layer per non-empty slot **in this exact order**.

---

## 3. Trait sheet rules (what ComfyUI must emit)

For each trait value, emit compact horizontal **strips**, one per animation:

```
assets/traits/<category>/<value>/maz_<anim>.png
   e.g. assets/traits/headwear/crown/maz_idle.png
```

1. **Canvas:** identical W×H to the canonical base sheet for that anim (§1). Reject
   anything else.
2. **Frames:** same count and same `frame_boxes()` cuts as the base. Frame *i* of the
   overlay aligns 1:1 with frame *i* of the base.
3. **Transparency:** fully transparent everywhere except the trait's own pixels
   (produced by base-subtraction, `extract_overlay.py`).
4. **Format:** RGBA PNG, straight (un-premultiplied) alpha. Palette-quantize is allowed
   but base and overlay must share consistent color so subtraction is clean.
5. **Compact strip only:** ONE file per (trait, anim). **No exploded per-frame PNGs.**
   No `_00001_` ComfyUI raw filenames. No square 1024×1024 canvases.

### Naming convention
- Category folder = `trait_type` lowercased (`"Headwear"` → `headwear`).
- Value folder = value lowercased, spaces → underscores (`"Party Hat"` → `party_hat`).
- File = `maz_<anim>.png` where `<anim> ∈ {idle, walk, run, jump}`.
- Base sheets: `assets/maz_<anim>.png` (canonical) and per-game copies keep their own
  path but must be regenerable by scaling the canonical composite (§5).

### Trait roster (categories → values), from `traits/README.md` + `BOSHI_PIPELINE.md`
- **Headwear:** crown, beanie, wizard_cap, party_hat, bandana, none
- **Eyes:** sharp, visor, laser, anime, heart, regular
- **Mouth:** grin, fang, tongue, smirk
- **Clothing:** suit, hoodie, tank_top, cloak, overalls, … (see `BoshiCore/clothes_*`)
- **Accessory:** chain, eyepatch, gold_chain, dog_tags, earrings, leash, gold_sword,
  plasma_wand, fire_staff, mystic_wand
- **Fur:** PALETTE hue-shift only — do not generate sheets.

---

## 4. Generation pipeline (in register, no exploded frames)

The proven path is `tools/spritegen/run.py` **transform mode** + `extract_overlay.py`:

```
maz_<anim>.png (canonical strip)
  → slice at frame_boxes()
  → ComfyUI img2img/edit @ denoise ~0.5  (Qwen-Image-Edit / Z-Image, same canvas)
  → resize each result back to its exact frame box
  → bg_remove (rembg u2netp, or black-bg flood-fill fallback)
  → normalize_frames() (one height, shared feet baseline, centered)
  → pack_sheet() → compact strip at canonical W×H
  → extract_overlay(naked_base, trait_on_base) → transparent overlay strip
```

**Forbidden:** dumping ComfyUI `SaveImage` output straight to `BoshiCore/` /
`Newgeneratedassets/`. That is the divergent path that broke registration. If ComfyUI
must save per-frame PNGs as an intermediate, they are **temp only** and MUST be repacked
into a canonical strip by `tools/comfy_conform.py` (this folder) before landing in
`assets/traits/`.

---

## 5. Per-game display scaling (after compositing)

Games render at different on-screen sizes. That is fine **as long as scaling happens on
the composited stack, never per trait layer**:

- **ShibTown/game** already does the right thing: `boshi_rig.gd` + `build_rig.py` measure
  content bounds and scale each *fully composited* boshi to a common character height with
  feet anchored. Feed it canonical-canvas sheets; it will scale down. Its current
  `boshi_*.png` (1768×584 etc.) should be **re-derived** from the canonical rig, not
  authored independently.
- **shadowcat-survivors** uses its own `maz_*.png` at 1098/1376/1836 widths. Regenerate
  those by compositing on the canonical canvas then scaling the whole sheet to the game's
  target width — do not re-author traits at the game width.

Rule: **one authoring canvas (this spec) → composite → scale per game.** Never scale a
single trait layer to fit a base of a different size.

---

## 6. Conformance checklist (CI-style gate)

A trait/base sheet is spec-conformant iff:

- [ ] path matches `assets/traits/<cat>/<value>/maz_<anim>.png` or `assets/maz_<anim>.png`
- [ ] dimensions exactly equal the §1 canonical W×H for that anim
- [ ] it is a single strip (not N per-frame files); width divides into the spec frame count
- [ ] RGBA with real transparency (overlays: transparent outside trait pixels)
- [ ] no `_NNNNN_` ComfyUI raw suffix in the filename
- [ ] frame count matches §1

`tools/comfy_conform.py --check assets/traits` enforces all of the above and is safe to
wire into a pre-export step.

---

## 7. Migration of the current mess (non-destructive)

1. Treat `BoshiCore/` (670 MB, 1,643 exploded PNGs) and `Newgeneratedassets/` (1024²) as
   **raw intermediates**, not deliverables. Do not ship them; do not stack from them.
2. Run `comfy_conform.py --repack BoshiCore --out assets/traits` to fold the exploded
   frames into canonical strips (grouped by `<cat>_<value>_<anim>_<NN>`), scaling the 1024²
   content onto the canonical canvas with feet-anchor + center.
3. Re-derive off-canvas overlays in `assets/traits` (the 1768×584 / 1448×720 / 1320×380
   ones) onto the canonical canvas the same way.
4. Re-derive each game's local base sheets from the canonical composite per §5.
5. Gate every future generation through `comfy_conform.py --check`.
```
