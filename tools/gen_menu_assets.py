#!/usr/bin/env python3
"""ShibKart-web MENU/UI art — ALL via the shared silhouette-edit pipeline (no LoRA).
Prompts from tools/asset_prompts.json.

Assets:  ui/logo.png ui/logo_bone.png ui/logo_treat.png (optional mascot emblems),
         ui/hero_bg.png ui/panel.png ui/ic_*.png
The menu renders a crisp CSS text wordmark if logo.png is absent, so logos are OPTIONAL.

RUN (from the ShibKart-web folder):
    cd ShibKart-web
    python tools/gen_menu_assets.py --validate   # offline
    python tools/gen_menu_assets.py --only logo   # just the emblem
    python tools/gen_menu_assets.py               # all menu art (ComfyUI running)
"""
import sys, json, argparse
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

HERE = Path(__file__).resolve().parent
WEB = HERE.parent
OUT = WEB / "public" / "assets" / "ui"
SPRITEGEN = WEB.parent / "gamedev" / "tools" / "spritegen"
P = json.loads((HERE / "asset_prompts.json").read_text())
STYLE, NEGB, Q, NEG = P["style_anchor"], P["negative_base"], P["quality"], P["negative"]
compose = lambda subj, cat: f"{subj}, {STYLE}, {Q.get(cat, '')}"

# logos are now just more edit-pipeline assets (folder ui)
SPECS = [dict(m) for m in P["menu"]] + [dict(it) for it in P["logos"]["items"]]

def draw_silhouette(shape, w, h, opaque):
    img = Image.new("RGBA", (w, h), (128, 128, 128, 255) if opaque else (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    if shape == "scene":
        d.rectangle([0, int(h * 0.55), w, h], fill=(90, 95, 110, 255)); d.ellipse([int(w * 0.3), int(h * 0.5), int(w * 0.7), int(h * 0.85)], fill=(230, 120, 60, 255))
    elif shape == "panel":
        d.rounded_rectangle([int(w * 0.08), int(h * 0.08), int(w * 0.92), int(h * 0.92)], radius=int(w * 0.12), fill=(150, 110, 210, 255))
    elif shape == "badge":
        d.ellipse([w * 0.14, h * 0.12, w * 0.86, h * 0.88], fill=(240, 190, 70, 255)); d.ellipse([w * 0.34, h * 0.3, w * 0.66, h * 0.7], fill=(235, 150, 70, 255))
    else:
        d.ellipse([w * 0.2, h * 0.2, w * 0.8, h * 0.8], fill=(230, 150, 70, 255))
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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--validate", action="store_true"); ap.add_argument("--only"); ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    if a.validate:
        for s in SPECS:
            (OUT).mkdir(parents=True, exist_ok=True)
            assert draw_silhouette(s["shape"], s["size"][0], s["size"][1], not s["transparent"]).size == tuple(s["size"])
            print(f"  [ok] ui/{s['name']}.png {s['size'][0]}x{s['size'][1]} transparent={s['transparent']}")
        print(f"\n{len(SPECS)} menu assets -> PASS (offline). Logos are optional (CSS wordmark fallback).")
        return 0
    if (SPRITEGEN / "run.py").exists(): sys.path.insert(0, str(SPRITEGEN))
    try:
        import run as R
    except Exception as e:
        print("!! spritegen client not found:", e); return 2
    workflow = json.loads((SPRITEGEN / "workflow.json").read_text()); OUT.mkdir(parents=True, exist_ok=True)
    for s in SPECS:
        if a.only and s["name"] != a.only: continue
        dest = OUT / f"{s['name']}.png"
        if dest.exists() and not a.force: print(f"  [skip] {s['name']}"); continue
        sil = draw_silhouette(s["shape"], s["size"][0], s["size"][1], not s["transparent"])
        seed = R._seed(s["name"]) if hasattr(R, "_seed") else 11
        img = R.render_transform(workflow, sil, compose(s["subject"], s["category"]), seed, float(s["denoise"]), f"shibkart_menu_{s['name']}", pad_square=s["transparent"])
        if s["transparent"]: img = corner_flood(img)
        img.convert("RGBA").resize(tuple(s["size"]), Image.LANCZOS).save(dest)
        print(f"  [ok] assets/ui/{s['name']}.png")
    print("\nDONE menu art.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
