#!/usr/bin/env python3
"""
comfy_conform.py — make ComfyUI trait output obey the BoshiCore canonical rig.

This is the reconciliation layer required by _boshicore_canon/RIG_SPEC.md. It does
NOT talk to ComfyUI itself (run.py already does that correctly in transform mode);
it (a) validates that sheets are on the canonical canvas, and (b) repacks the
degraded, EXPLODED per-frame 1024x1024 dumps in BoshiCore/ / Newgeneratedassets/
into compact, in-register strips at the canonical dimensions.

Why this exists: a divergent path wrote raw ComfyUI SaveImage output
(`<trait>_<anim>_<NN>_00001_.png`, 1024x1024, one file per frame) straight to disk,
bypassing run.py's slice->transform->bg_remove->normalize->pack. That exploded into
670 MB and destroyed registration/pivots so trait stacking broke. This tool folds
those frames back onto the canonical rig.

Usage:
    # Fail (exit 1) on any sheet that violates the spec canvas / naming.
    python3 comfy_conform.py --check ../assets/traits

    # Repack exploded per-frame dumps -> canonical strips under assets/traits/.
    python3 comfy_conform.py --repack ../BoshiCore --out ../assets/traits
    python3 comfy_conform.py --repack ../Newgeneratedassets --out ../assets/traits

    # Re-scale an off-canvas strip onto the canonical canvas.
    python3 comfy_conform.py --recanvas ../assets/traits/eyes/laser/maz_idle.png

Requires: pillow, numpy.  Reuses run.py helpers when importable.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image

# ---- Canonical rig (mirrors RIG_SPEC.md §1). Single source of truth in code. ----
CANON = {
    "idle": {"w": 1768, "h": 584, "frames": 6, "fps": 9},
    "walk": {"w": 1448, "h": 720, "frames": 8, "fps": 14},
    "run":  {"w": 1448, "h": 720, "frames": 6, "fps": 16},
    "jump": {"w": 1448, "h": 720, "frames": 4, "fps": 10},
}
ANIMS = tuple(CANON.keys())
RAW_SUFFIX_RE = re.compile(r"_(\d{5})_?\.png$")          # ComfyUI SaveImage counter
# <category>_<value>_<anim>_<frameNN>[_00001].png  (exploded dump naming)
EXPLODED_RE = re.compile(
    r"^(?P<cat>[a-z]+)_(?P<val>.+?)_(?P<anim>idle|walk|run|jump)_(?P<idx>\d{2})(?:_\d+)?_?\.png$"
)


def frame_boxes(width: int, n: int) -> list[tuple[int, int]]:
    """Rounded fractional cuts so non-integer frame widths still tile exactly.
    Identical to run.py.frame_boxes so strips stay in register."""
    return [(round(i * width / n), round((i + 1) * width / n)) for i in range(n)]


# ---- optional: reuse the proven post helpers from run.py -------------------------
def _load_run_helpers():
    here = Path(__file__).resolve()
    spritegen = here.parents[2] / "tools" / "spritegen"
    if spritegen.is_dir():
        sys.path.insert(0, str(spritegen))
        try:
            import run  # type: ignore
            return run.bg_remove, run.normalize_frames
        except Exception:
            pass
    return None, None


_BG_REMOVE, _NORMALIZE = _load_run_helpers()


def _fallback_bg_remove(im: Image.Image, thr: int = 42) -> Image.Image:
    """Border flood-fill: clear background-connected near-black pixels only."""
    from collections import deque
    rgba = im.convert("RGBA"); w, h = rgba.size; px = rgba.load()
    def is_bg(x, y):
        r, g, b, _ = px[x, y]; return (r + g + b) <= thr * 3
    seen = bytearray(w * h); dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y) and not seen[y*w+x]:
                seen[y*w+x] = 1; dq.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y) and not seen[y*w+x]:
                seen[y*w+x] = 1; dq.append((x, y))
    while dq:
        x, y = dq.popleft(); px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny*w+nx] and is_bg(nx, ny):
                seen[ny*w+nx] = 1; dq.append((nx, ny))
    return rgba


def bg_remove(im: Image.Image) -> Image.Image:
    return _BG_REMOVE(im) if _BG_REMOVE else _fallback_bg_remove(im)


def anchor_to_box(frame: Image.Image, box_w: int, box_h: int) -> Image.Image:
    """Scale a (bg-removed) frame's content to fit box_h and stand it feet-on-
    baseline, centered — mapping an off-rig frame (e.g. 1024x1024) onto a canonical
    frame box so it stacks in register."""
    rgba = frame.convert("RGBA")
    bb = rgba.getbbox()
    canvas = Image.new("RGBA", (box_w, box_h), (0, 0, 0, 0))
    if bb is None:
        return canvas
    crop = rgba.crop(bb)
    cw, ch = crop.size
    scale = min(box_w / cw, box_h / ch)
    nw, nh = max(1, round(cw * scale)), max(1, round(ch * scale))
    scaled = crop.resize((nw, nh), Image.LANCZOS)
    canvas.alpha_composite(scaled, ((box_w - nw) // 2, box_h - nh))  # feet on baseline
    return canvas


# ---------------------------------- CHECK ----------------------------------------
def check(root: Path) -> int:
    problems: list[str] = []
    strips = 0
    for p in sorted(root.rglob("*.png")):
        name = p.name
        if RAW_SUFFIX_RE.search(name):
            problems.append(f"[raw-suffix] {p} — looks like an exploded ComfyUI dump")
            continue
        m = re.match(r"^maz_(idle|walk|run|jump)\.png$", name)
        if not m:
            # tolerate non-sheet files, but flag base-like names on wrong pattern
            continue
        anim = m.group(1); c = CANON[anim]
        try:
            w, h = Image.open(p).size
        except Exception as e:
            problems.append(f"[unreadable] {p}: {e}"); continue
        if (w, h) != (c["w"], c["h"]):
            problems.append(f"[canvas] {p} is {w}x{h}, spec {anim}={c['w']}x{c['h']}")
        elif w % c["frames"] and (w / c["frames"]) != round(w / c["frames"]):
            # non-integer frame width is allowed (rounded cuts) — informational only
            strips += 1
        else:
            strips += 1
    for msg in problems:
        print("  FAIL " + msg)
    print(f"\n{strips} conformant sheet(s), {len(problems)} problem(s) in {root}")
    return 1 if problems else 0


# --------------------------------- REPACK ----------------------------------------
def repack(src: Path, out: Path) -> int:
    """Group exploded per-frame PNGs by (cat, val, anim) and fold them into a
    single canonical strip at assets/traits/<cat>/<val>/maz_<anim>.png."""
    groups: dict[tuple[str, str, str], list[tuple[int, Path]]] = defaultdict(list)
    skipped = 0
    for p in sorted(src.glob("*.png")):
        m = EXPLODED_RE.match(p.name)
        if not m:
            skipped += 1; continue
        key = (m["cat"], m["val"], m["anim"])
        groups[key].append((int(m["idx"]), p))

    written = 0
    for (cat, val, anim), items in sorted(groups.items()):
        c = CANON.get(anim)
        if not c:
            print(f"  [skip] unknown anim {anim} for {cat}/{val}"); continue
        items.sort()
        n_have = len(items)
        if n_have != c["frames"]:
            print(f"  [warn] {cat}/{val}/{anim}: {n_have} frames, spec wants {c['frames']} "
                  f"(packing what exists, will not fabricate)")
        boxes = frame_boxes(c["w"], c["frames"])
        strip = Image.new("RGBA", (c["w"], c["h"]), (0, 0, 0, 0))
        frames = []
        for _, fp in items[: c["frames"]]:
            frames.append(bg_remove(Image.open(fp).convert("RGBA")))
        # place each frame anchored into its canonical box (scaled from 1024^2)
        placed = []
        for i, (x0, x1) in enumerate(boxes):
            if i >= len(frames):
                break
            placed.append(anchor_to_box(frames[i], x1 - x0, c["h"]))
        if _NORMALIZE:
            placed = _NORMALIZE(placed)
        for (x0, x1), fr in zip(boxes, placed):
            strip.alpha_composite(fr, (x0, 0))
        dest = out / cat / val.replace(" ", "_") / f"maz_{anim}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        strip.save(dest)
        written += 1
        print(f"  [ok] {dest}  ({len(placed)} frames @ {c['w']}x{c['h']})")
    print(f"\nrepacked {written} strip(s) from {src}; {skipped} non-matching file(s) skipped")
    return 0


def recanvas(path: Path) -> int:
    m = re.match(r"^maz_(idle|walk|run|jump)\.png$", path.name)
    if not m:
        print(f"  cannot infer anim from {path.name} (expect maz_<anim>.png)"); return 1
    anim = m.group(1); c = CANON[anim]
    src = Image.open(path).convert("RGBA")
    if src.size == (c["w"], c["h"]):
        print(f"  already canonical ({c['w']}x{c['h']})"); return 0
    # slice on the SOURCE's own frame boxes, re-anchor into canonical boxes
    sboxes = frame_boxes(src.width, c["frames"])
    dboxes = frame_boxes(c["w"], c["frames"])
    out = Image.new("RGBA", (c["w"], c["h"]), (0, 0, 0, 0))
    frames = [anchor_to_box(src.crop((x0, 0, x1, src.height)), dx1 - dx0, c["h"])
              for (x0, x1), (dx0, dx1) in zip(sboxes, dboxes)]
    if _NORMALIZE:
        frames = _NORMALIZE(frames)
    for (x0, _), fr in zip(dboxes, frames):
        out.alpha_composite(fr, (x0, 0))
    bak = path.with_suffix(".pre_recanvas.png")
    if not bak.exists():
        path.rename(bak)
    out.save(path)
    print(f"  recanvased {path} {src.size} -> {c['w']}x{c['h']} (backup: {bak.name})")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Conform ComfyUI trait output to the BoshiCore rig spec.")
    ap.add_argument("--check", metavar="DIR", help="validate sheets under DIR against the spec")
    ap.add_argument("--repack", metavar="SRC", help="fold exploded per-frame PNGs in SRC into strips")
    ap.add_argument("--out", metavar="DIR", help="destination traits root for --repack")
    ap.add_argument("--recanvas", metavar="PNG", help="rescale one off-canvas strip onto canonical canvas")
    args = ap.parse_args()

    if args.check:
        return check(Path(args.check))
    if args.repack:
        if not args.out:
            print("--repack requires --out"); return 2
        return repack(Path(args.repack), Path(args.out))
    if args.recanvas:
        return recanvas(Path(args.recanvas))
    ap.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
