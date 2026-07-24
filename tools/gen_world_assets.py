#!/usr/bin/env python3
"""ShibKart-web WORLD/GAME art (ComfyUI silhouette-edit) + free procedural skyboxes.
Prompts come from tools/asset_prompts.json (single hardened source of truth).

Folders / filenames MATCH what the code loads:
  public/assets/track/  road_<theme>.png ground_<theme>.png kerb.png sponsor_1..3.png  (8 themes)
  public/assets/kart/   livery_*.png       public/assets/items/  <item>.png
  public/assets/sky/    <theme>.png  (procedural gradient, no ComfyUI)

RUN:  python tools/gen_world_assets.py --validate | --skybox | (no args = all)
"""
import sys, json, argparse
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

HERE = Path(__file__).resolve().parent
WEB = HERE.parent
A = WEB / "public" / "assets"
SPRITEGEN = WEB.parent / "gamedev" / "tools" / "spritegen"
P = json.loads((HERE / "asset_prompts.json").read_text())
STYLE, NEGB, Q, NEG = P["style_anchor"], P["negative_base"], P["quality"], P["negative"]
TILE_ANCHOR = P.get("tile_anchor", STYLE)
compose = lambda subj, cat: f"{subj}, {TILE_ANCHOR if cat=='tile' else STYLE}, {Q.get(cat, '')}"
TILE_DENOISE = P.get("_tile_denoise", 0.85)
negof = lambda cat: f"{NEGB}, {NEG.get(cat, '')}"

THEMES = ["grass", "cherry", "city", "desert", "moon", "snow", "volcano", "beach"]
SPECS = []
for th, subj in P["tiles_road"].items():
    SPECS.append(dict(folder="track", name=f"road_{th}", size=[512, 512], transparent=False, tileable=True, denoise=P.get("_tile_denoise",0.85), shape="tile", cat="tile", subject=subj))
for th, subj in P["tiles_ground"].items():
    SPECS.append(dict(folder="track", name=f"ground_{th}", size=[512, 512], transparent=False, tileable=True, denoise=P.get("_tile_denoise",0.85), shape="tile", cat="tile", subject=subj))
for m in P["misc_world"]:
    SPECS.append(dict(folder=m["folder"], name=m["name"], size=m["size"], transparent=m["transparent"], tileable=m.get("tileable", False), denoise=m["denoise"], shape=m["shape"], cat=m["category"], subject=m["subject"]))

SKY = {"grass": (0x8fd0ff, 0xdff0ff), "cherry": (0xffb0d8, 0xffe6f2), "city": (0x1a2350, 0x3a2a6a), "desert": (0x7ec0ff, 0xf3e0b0), "moon": (0x05060f, 0x1a1030), "snow": (0xbfe0ff, 0xeaf4ff), "volcano": (0x3a1010, 0xe0602a), "beach": (0x2aa0e0, 0xbfeaff)}

def draw_silhouette(shape, w, h, opaque):
    img = Image.new("RGBA", (w, h), (128, 128, 128, 255) if opaque else (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    if shape == "stripe":
        for i in range(-h, w, h): d.polygon([(i, 0), (i + h, 0), (i + h * 2, h), (i + h, h)], fill=(220, 60, 60, 255) if (i // h) % 2 else (240, 240, 240, 255))
    elif shape == "sign":
        d.rectangle([0, 0, w, h], fill=(66, 140, 210, 255)); d.rectangle([w * 0.1, h * 0.3, w * 0.9, h * 0.62], fill=(242, 202, 64, 255))
    elif shape == "decal":
        d.polygon([(0, h), (w * 0.6, h * 0.2), (w, h * 0.4), (w, h)], fill=(230, 120, 60, 255))
    elif shape == "icon":
        d.ellipse([w * 0.2, h * 0.2, w * 0.8, h * 0.8], fill=(230, 150, 70, 255))
    else:
        base = np.random.default_rng(1).integers(70, 120, (h, w, 3)).astype("uint8")
        img = Image.fromarray(np.dstack([base, np.full((h, w), 255, "uint8")]), "RGBA")
    return img

def corner_flood(img, tol=74):
    img = img.convert("RGBA"); a = np.asarray(img).astype(np.int16)
    border = np.concatenate([a[0, :, :3], a[-1, :, :3], a[:, 0, :3], a[:, -1, :3]])
    bg = np.median(border, axis=0); m = np.sqrt(((a[:, :, :3] - bg) ** 2).sum(2)) < tol
    try:
        from scipy import ndimage
        lbl, _ = ndimage.label(m); keep = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1]); keep.discard(0)
        rem = np.isin(lbl, list(keep))
    except Exception:
        rem = m
    out = a.astype(np.uint8); out[rem, 3] = 0
    return Image.fromarray(out, "RGBA")

def make_seamless(img):
    a = np.asarray(img.convert("RGB")).astype(float); h, w, _ = a.shape
    off = np.roll(np.roll(a, w // 2, 1), h // 2, 0)
    xs = 1 - np.abs(np.linspace(-1, 1, w)); ys = 1 - np.abs(np.linspace(-1, 1, h))
    m = np.minimum.outer(ys, xs)[..., None]
    return Image.fromarray((a * m + off * (1 - m)).astype("uint8"))

def gen_skyboxes():
    out = A / "sky"; out.mkdir(parents=True, exist_ok=True)
    W, Hh = 1024, 512
    for theme, (top, hor) in SKY.items():
        tc = np.array([(top >> 16) & 255, (top >> 8) & 255, top & 255], float)
        hc = np.array([(hor >> 16) & 255, (hor >> 8) & 255, hor & 255], float)
        g = np.zeros((Hh, W, 3), "uint8")
        for y in range(Hh): g[y, :] = (tc * (1 - y / (Hh - 1)) + hc * (y / (Hh - 1))).astype("uint8")
        Image.fromarray(g).save(out / f"{theme}.png"); print(f"  [ok] assets/sky/{theme}.png")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--validate", action="store_true"); ap.add_argument("--skybox", action="store_true")
    ap.add_argument("--only"); ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if args.validate:
        for s in SPECS:
            (A / s["folder"]).mkdir(parents=True, exist_ok=True)
            assert draw_silhouette(s["shape"], s["size"][0], s["size"][1], not s["transparent"]).size == tuple(s["size"])
            print(f"  [ok] {s['folder']}/{s['name']}.png {s['size'][0]}x{s['size'][1]} tileable={s['tileable']}")
        print(f"  skyboxes: {', '.join(SKY)}")
        print(f"\n{len(SPECS)} textures + {len(SKY)} skyboxes -> PASS (offline)")
        return 0
    gen_skyboxes()
    if args.skybox: return 0
    if (SPRITEGEN / "run.py").exists(): sys.path.insert(0, str(SPRITEGEN))
    try:
        import run as R
    except Exception as e:
        print("!! spritegen client not found:", e, "\n   (skyboxes generated; textures need ComfyUI)"); return 2
    workflow = json.loads((SPRITEGEN / "workflow.json").read_text())
    for s in SPECS:
        if args.only and s["name"] != args.only: continue
        dest = A / s["folder"] / f"{s['name']}.png"; dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() and not args.force: print(f"  [skip] {s['name']}"); continue
        sil = draw_silhouette(s["shape"], s["size"][0], s["size"][1], not s["transparent"])
        seed = R._seed(s["name"]) if hasattr(R, "_seed") else 7
        img = R.render_transform(workflow, sil, compose(s["subject"], s["cat"]), seed, float(s["denoise"]), f"shibkart_{s['folder']}_{s['name']}", pad_square=s["transparent"])
        if s["transparent"]: img = corner_flood(img)
        elif s.get("tileable"): img = make_seamless(img)
        img.convert("RGBA").resize(tuple(s["size"]), Image.LANCZOS).save(dest)
        print(f"  [ok] assets/{s['folder']}/{s['name']}.png")
    print("\nDONE world art.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
