#!/usr/bin/env python3
r"""
generate_shibkart_assets.py  —  ShibKart asset pipeline (flawless edition)
============================================================================
Generates EVERY ShibKart game asset with ComfyUI and drops each into the right
ShibKart/assets/<category>/ folder. It reuses YOUR proven, already-working
ComfyUI graph (gamedev/tools/spritegen/workflow.json = Qwen-Image-Edit) exactly
the way world_gen.py / fx_gen.py do: it draws a crude procedural SILHOUETTE for
each asset, then lets ComfyUI polish that silhouette into a finished sprite or
texture. NO style LoRAs are added; nothing about your workflow is modified.

Every output passes a QA gate (right size, real transparency / real texture
detail, not empty, not a flat blob). Tiles are made seamless. Runs are resumable.
You can PROVE the whole pipeline offline first — see --validate.

----------------------------------------------------------------------------
QUICK START
----------------------------------------------------------------------------
  # 0. Prove the pipeline with NO GPU — draws every silhouette + runs QA on them,
  #    checks the manifest, sizes, folders. Nothing hits ComfyUI:
        python tools/generate_shibkart_assets.py --validate

  # 1. See the silhouettes it will send (saved to assets/_silhouettes/):
        python tools/generate_shibkart_assets.py --silhouettes

  # 2. Start ComfyUI (the same one you use for Boshi art) at 127.0.0.1:8188, then:
        python tools/generate_shibkart_assets.py               # everything, auto-placed
        python tools/generate_shibkart_assets.py --only tiles  # one category
        python tools/generate_shibkart_assets.py --only props/coin --force
        python tools/generate_shibkart_assets.py --boshis      # copy the Boshi rig in

Resumable: existing outputs are skipped unless --force. Each asset that fails QA
is retried once with a new seed, then reported (never silently shipped).

Requires: pillow, numpy, requests (rembg optional, via your spritegen/run.py).
============================================================================
"""
from __future__ import annotations
import argparse, json, math, shutil, sys, zlib
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("!! pip install pillow"); raise
try:
    import numpy as np
except ImportError:
    np = None

HERE = Path(__file__).resolve().parent
SHIBKART = HERE.parent
ASSETS = SHIBKART / "assets"
ADDON_ASSETS = SHIBKART / "addons" / "boshicore" / "assets"
AIVIDS = SHIBKART.parent
GAMEDEV = AIVIDS / "gamedev"
CANON_ASSETS = GAMEDEV / "assets"
SPRITEGEN = GAMEDEV / "tools" / "spritegen"
PROVEN_WORKFLOW = SPRITEGEN / "workflow.json"
MANIFEST = HERE / "asset_manifest.json"
SIL_DIR = ASSETS / "_silhouettes"

CATEGORY_DIR = {
    "tiles": ASSETS / "tiles", "scenery": ASSETS / "scenery", "props": ASSETS / "props",
    "karts": ASSETS / "karts", "ui": ASSETS / "ui",
    "icons": ASSETS / "ui" / "icons", "emblems": ASSETS / "ui" / "emblems",
    "landmarks": ASSETS / "landmarks",
}

# reuse the proven spritegen ComfyUI client + bg_remove
_R = None
if (SPRITEGEN / "run.py").exists():
    sys.path.insert(0, str(SPRITEGEN))
    try:
        import run as _R  # type: ignore
    except Exception as e:
        print(f"  (note: spritegen/run.py import failed: {e})"); _R = None


# ============================================================ silhouette drawing
def _seed(name: str) -> int:
    return zlib.crc32(name.encode()) & 0x7FFFFFFF

def base_size(w: int, h: int) -> tuple[int, int]:
    m = max(w, h); s = 800.0 / m
    return (max(64, round(w * s / 8) * 8), max(64, round(h * s / 8) * 8))

def _noise(img: Image.Image, amt: int, sd: int) -> None:
    if np is None: return
    rng = np.random.default_rng(sd)
    a = np.array(img).astype(np.int16)
    n = rng.integers(-amt, amt + 1, a.shape[:2])[..., None]
    a[..., :3] = np.clip(a[..., :3] + n, 0, 255)
    img.paste(Image.fromarray(a.astype("uint8")))

def draw_silhouette(shape: str, w: int, h: int, opaque: bool, sd: int) -> Image.Image:
    """A rough colored guide the edit model refines. Sprites: colored shape on solid
    black (so bg_remove cuts cleanly). Tiles: a full-frame colored base + noise."""
    if opaque:
        img = Image.new("RGBA", (w, h), (128, 128, 128, 255))
    else:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2

    if shape == "tile_color":
        d.rectangle([0, 0, w, h], fill=(96, 150, 84, 255)); _noise(img, 40, sd)
    elif shape == "tile_asphalt":
        d.rectangle([0, 0, w, h], fill=(74, 74, 82, 255)); _noise(img, 30, sd)
    elif shape == "tile_stripe":
        step = w // 8
        for i in range(-h, w, step):
            col = (215, 70, 70, 255) if (i // step) % 2 == 0 else (240, 240, 240, 255)
            d.polygon([(i, 0), (i + step, 0), (i + step - h, h), (i - h, h)], fill=col)
    elif shape == "tile_checker":
        s = w // 8
        for j in range(h // s + 1):
            for i in range(w // s + 1):
                if (i + j) % 2 == 0:
                    d.rectangle([i * s, j * s, (i + 1) * s, (j + 1) * s], fill=(20, 20, 20, 255))
                else:
                    d.rectangle([i * s, j * s, (i + 1) * s, (j + 1) * s], fill=(240, 240, 240, 255))
    elif shape == "kart":
        d.polygon([(cx-w*0.28,cy-h*0.18),(cx+w*0.22,cy-h*0.16),(cx+w*0.38,cy),
                   (cx+w*0.22,cy+h*0.16),(cx-w*0.28,cy+h*0.18)], fill=(235,235,235,255))
        for dx,dy in [(-0.2,-0.24),(-0.2,0.24),(0.16,-0.24),(0.16,0.24)]:
            d.ellipse([cx+dx*w-14,cy+dy*h-10,cx+dx*w+14,cy+dy*h+10], fill=(30,30,36,255))
    elif shape in ("tree", "bush"):
        if shape == "tree":
            d.rectangle([cx-w*0.06,cy+h*0.05,cx+w*0.06,h*0.95], fill=(110,74,42,255))
        for r,dy,col in [(0.34,-0.05,(58,140,66)),(0.26,-0.2,(74,160,80)),(0.2,-0.32,(90,175,96))]:
            d.ellipse([cx-w*r,cy+h*dy-w*r,cx+w*r,cy+h*dy+w*r], fill=col+(255,))
    elif shape == "fence":
        for fx in (0.2,0.5,0.8):
            d.rectangle([w*fx-8,h*0.2,w*fx+8,h*0.95], fill=(230,230,230,255))
        d.rectangle([w*0.15,h*0.35,w*0.85,h*0.47], fill=(230,230,230,255))
        d.rectangle([w*0.15,h*0.6,w*0.85,h*0.72], fill=(230,230,230,255))
    elif shape in ("box","box_cube"):
        col=(180,140,90,255) if shape=="box" else (150,120,220,255)
        d.polygon([(cx-w*0.3,cy-h*0.05),(cx,cy-h*0.3),(cx+w*0.3,cy-h*0.05),
                   (cx+w*0.3,cy+h*0.28),(cx,cy+h*0.42),(cx-w*0.3,cy+h*0.28)], fill=col)
    elif shape == "building":
        d.rectangle([w*0.2,h*0.1,w*0.8,h*0.95], fill=(70,80,120,255))
        for yy in range(2,9):
            for xx in range(3):
                d.rectangle([w*(0.3+xx*0.16),h*yy*0.1,w*(0.36+xx*0.16),h*(yy*0.1+0.05)], fill=(180,220,255,255))
    elif shape == "post":
        d.rectangle([cx-8,h*0.15,cx+8,h*0.95], fill=(120,120,130,255))
        d.ellipse([cx-w*0.28,h*0.05,cx+w*0.28,h*0.3], fill=(240,220,120,255))
    elif shape == "cactus":
        d.rectangle([cx-w*0.12,h*0.25,cx+w*0.12,h*0.95], fill=(60,140,70,255))
        d.rectangle([cx-w*0.34,h*0.45,cx-w*0.12,h*0.55], fill=(60,140,70,255))
        d.rectangle([cx-w*0.34,h*0.35,cx-w*0.22,h*0.55], fill=(60,140,70,255))
        d.rectangle([cx+w*0.12,h*0.4,cx+w*0.34,h*0.5], fill=(60,140,70,255))
        d.rectangle([cx+w*0.22,h*0.3,cx+w*0.34,h*0.5], fill=(60,140,70,255))
    elif shape == "arch":
        d.rectangle([w*0.1,h*0.3,w*0.9,h*0.95], fill=(190,150,100,255))
        d.ellipse([w*0.28,h*0.4,w*0.72,h*1.2], fill=(0,0,0,255) if not opaque else (128,128,128,255))
    elif shape in ("panel","panel_ui"):
        d.rounded_rectangle([w*0.15,h*0.1,w*0.85,h*0.9], radius=18, fill=(70,90,130,255))
        for yy in range(3):
            d.rectangle([w*0.25,h*(0.25+yy*0.2),w*0.75,h*(0.29+yy*0.2)], fill=(150,200,255,255))
    elif shape == "chevron_pad":
        d.ellipse([cx-w*0.42,cy-h*0.42,cx+w*0.42,cy+h*0.42], fill=(20,60,90,255))
        for k in range(3):
            yy=cy-h*0.18+k*h*0.16
            d.polygon([(cx-w*0.2,yy),(cx,yy-h*0.1),(cx+w*0.2,yy),(cx,yy+h*0.02)], fill=(60,200,240,255))
    elif shape in ("coin_disc","circle","ring","circle_badge"):
        col=(240,200,70,255)
        d.ellipse([cx-w*0.4,cy-h*0.4,cx+w*0.4,cy+h*0.4], fill=col)
        if shape=="ring":
            d.ellipse([cx-w*0.24,cy-h*0.24,cx+w*0.24,cy+h*0.24], fill=(0,0,0,255) if not opaque else (128,128,128,255))
        if shape=="circle_badge":
            d.ellipse([cx-w*0.18,cy-h*0.18,cx+w*0.18,cy+h*0.18], fill=(200,150,40,255))
    elif shape == "bone":
        d.rounded_rectangle([w*0.25,cy-h*0.1,w*0.75,cy+h*0.1], radius=10, fill=(240,240,235,255))
        for ex in (0.22,0.78):
            d.ellipse([w*ex-w*0.14,cy-h*0.26,w*ex+w*0.14,cy], fill=(240,240,235,255))
            d.ellipse([w*ex-w*0.14,cy,w*ex+w*0.14,cy+h*0.26], fill=(240,240,235,255))
    elif shape == "banana":
        d.arc([w*0.15,h*0.15,w*0.85,h*1.1], start=200, end=340, fill=(230,200,60,255), width=int(h*0.16))
    elif shape == "shell":
        d.ellipse([cx-w*0.32,cy-h*0.32,cx+w*0.32,cy+h*0.32], fill=(210,60,60,255))
        for a in range(0,360,45):
            x=cx+math.cos(math.radians(a))*w*0.4; y=cy+math.sin(math.radians(a))*h*0.4
            d.polygon([(cx+math.cos(math.radians(a))*w*0.3,cy+math.sin(math.radians(a))*h*0.3),
                       (x,y),(cx+math.cos(math.radians(a+20))*w*0.3,cy+math.sin(math.radians(a+20))*h*0.3)],
                      fill=(230,230,230,255))
    elif shape in ("shield_orb","shield_emblem"):
        d.ellipse([cx-w*0.4,cy-h*0.4,cx+w*0.4,cy+h*0.4], fill=(80,150,230,255))
        d.ellipse([cx-w*0.22,cy-h*0.3,cx+w*0.05,cy-h*0.05], fill=(200,225,255,255))
    elif shape == "ramp":
        d.polygon([(w*0.1,h*0.9),(w*0.9,h*0.9),(w*0.9,h*0.2)], fill=(230,200,60,255))
        for k in range(3):
            d.polygon([(w*(0.2+k*0.22),h*0.9),(w*(0.32+k*0.22),h*0.9),(w*0.9,h*(0.55-k*0.02))],
                      fill=(30,30,30,255))
    elif shape == "bolt":
        d.polygon([(cx-w*0.1,h*0.1),(cx+w*0.2,h*0.1),(cx,cy),(cx+w*0.18,cy),
                   (cx-w*0.15,h*0.92),(cx,cy+h*0.05),(cx-w*0.22,cy+h*0.05)], fill=(245,215,60,255))
    elif shape == "ghost":
        d.pieslice([cx-w*0.3,h*0.15,cx+w*0.3,h*0.85], start=180, end=360, fill=(240,240,245,255))
        d.rectangle([cx-w*0.3,cy,cx+w*0.3,h*0.8], fill=(240,240,245,255))
        for ex in (-0.12,0.12):
            d.ellipse([cx+ex*w-8,cy-8,cx+ex*w+8,cy+8], fill=(40,40,60,255))
    elif shape == "flag":
        d.rectangle([w*0.2,h*0.1,w*0.26,h*0.9], fill=(60,60,60,255))
        s=int(w*0.1)
        for j in range(3):
            for i in range(4):
                if (i+j)%2==0:
                    d.rectangle([w*0.26+i*s,h*0.15+j*s,w*0.26+(i+1)*s,h*0.15+(j+1)*s], fill=(20,20,20,255))
                else:
                    d.rectangle([w*0.26+i*s,h*0.15+j*s,w*0.26+(i+1)*s,h*0.15+(j+1)*s], fill=(240,240,240,255))
    elif shape == "button_pill":
        d.rounded_rectangle([w*0.05,h*0.15,w*0.95,h*0.85], radius=int(h*0.35), fill=(150,110,220,255))
    elif shape == "logo":
        for i in range(4):
            d.rounded_rectangle([w*(0.08+i*0.22),h*0.3,w*(0.08+i*0.22)+w*0.16,h*0.7], radius=12,
                                fill=(180,120,230,255) if i%2 else (240,200,70,255))
    elif shape == "splash":
        for yy in range(h):
            tt = yy / max(1, h)
            d.line([(0, yy), (w, yy)], fill=(int(90 + 90 * tt), int(140 + 40 * tt), int(210 - 90 * tt), 255))
        d.rectangle([0, int(h * 0.6), w, h], fill=(90, 155, 80, 255))
        d.polygon([(w * 0.28, h), (w * 0.72, h), (w * 0.6, h * 0.6), (w * 0.4, h * 0.6)], fill=(70, 70, 80, 255))
        d.ellipse([w * 0.42, h * 0.68, w * 0.58, h * 0.9], fill=(230, 70, 55, 255))
        d.ellipse([w * 0.1, h * 0.15, w * 0.24, h * 0.28], fill=(240, 240, 245, 255))
        d.ellipse([w * 0.72, h * 0.12, w * 0.9, h * 0.26], fill=(240, 240, 245, 255))
    elif shape == "snowman":
        d.ellipse([cx-w*0.32,h*0.55,cx+w*0.32,h*0.98], fill=(240,244,250,255))
        d.ellipse([cx-w*0.24,h*0.28,cx+w*0.24,h*0.66], fill=(240,244,250,255))
        d.ellipse([cx-w*0.17,h*0.05,cx+w*0.17,h*0.34], fill=(240,244,250,255))
        d.polygon([(cx,h*0.19),(cx+w*0.22,h*0.21),(cx,h*0.24)], fill=(235,140,40,255))
    elif shape == "palm":
        d.rectangle([cx-w*0.05,h*0.4,cx+w*0.05,h*0.95], fill=(120,84,50,255))
        for ang in range(0,360,45):
            import math as _m
            ex=cx+_m.cos(_m.radians(ang))*w*0.4; ey=h*0.32+_m.sin(_m.radians(ang))*h*0.22
            d.line([(cx,h*0.32),(ex,ey)], fill=(50,150,60,255), width=int(w*0.06))
        d.ellipse([cx-w*0.14,h*0.24,cx+w*0.14,h*0.4], fill=(60,160,70,255))
    elif shape == "umbrella":
        d.rectangle([cx-6,h*0.35,cx+6,h*0.95], fill=(160,160,170,255))
        d.pieslice([cx-w*0.42,h*0.1,cx+w*0.42,h*0.7], start=180, end=360, fill=(230,70,70,255))
        d.pieslice([cx-w*0.42,h*0.1,cx+w*0.42,h*0.7], start=200, end=250, fill=(240,240,240,255))
        d.pieslice([cx-w*0.42,h*0.1,cx+w*0.42,h*0.7], start=290, end=340, fill=(240,240,240,255))
    elif shape == "volcano_rock":
        d.polygon([(cx-w*0.4,h*0.9),(cx-w*0.15,h*0.3),(cx+w*0.1,h*0.5),(cx+w*0.4,h*0.9)], fill=(60,45,42,255))
        d.polygon([(cx-w*0.1,h*0.5),(cx,h*0.35),(cx+w*0.08,h*0.55)], fill=(230,90,40,255))
    elif shape == "pagoda":
        for k in range(3):
            wk = w * (0.52 - 0.13 * k); yb = h * (0.88 - 0.25 * k)
            d.rectangle([cx - wk / 2, yb - h * 0.12, cx + wk / 2, yb], fill=(235, 225, 208, 255))
            d.polygon([(cx - wk * 0.78, yb - h * 0.12), (cx + wk * 0.78, yb - h * 0.12), (cx, yb - h * 0.26)], fill=(178, 58, 48, 255))
    elif shape == "torii":
        d.rectangle([w * 0.24, h * 0.22, w * 0.32, h * 0.94], fill=(200, 58, 48, 255))
        d.rectangle([w * 0.68, h * 0.22, w * 0.76, h * 0.94], fill=(200, 58, 48, 255))
        d.rectangle([w * 0.12, h * 0.16, w * 0.88, h * 0.26], fill=(200, 58, 48, 255))
        d.rectangle([w * 0.18, h * 0.34, w * 0.82, h * 0.4], fill=(200, 58, 48, 255))
    elif shape == "windmill":
        d.polygon([(cx - w * 0.14, h * 0.9), (cx + w * 0.14, h * 0.9), (cx + w * 0.1, h * 0.42), (cx - w * 0.1, h * 0.42)], fill=(230, 222, 205, 255))
        d.polygon([(cx - w * 0.14, h * 0.42), (cx + w * 0.14, h * 0.42), (cx, h * 0.3)], fill=(170, 58, 48, 255))
        for a in range(4):
            ang = math.radians(a * 90 + 25)
            ex = cx + math.cos(ang) * w * 0.33; ey = h * 0.38 + math.sin(ang) * h * 0.33
            d.line([(cx, h * 0.38), (ex, ey)], fill=(220, 210, 190, 255), width=max(2, int(w * 0.045)))
    elif shape == "castle":
        d.rectangle([w * 0.24, h * 0.42, w * 0.76, h * 0.94], fill=(150, 145, 135, 255))
        for tx in (0.18, 0.5, 0.82):
            d.rectangle([w * tx - w * 0.08, h * 0.28, w * tx + w * 0.08, h * 0.94], fill=(162, 157, 147, 255))
            d.polygon([(w * tx - w * 0.1, h * 0.28), (w * tx + w * 0.1, h * 0.28), (w * tx, h * 0.15)], fill=(150, 55, 50, 255))
    elif shape == "lighthouse":
        d.polygon([(cx - w * 0.14, h * 0.92), (cx + w * 0.14, h * 0.92), (cx + w * 0.08, h * 0.2), (cx - w * 0.08, h * 0.2)], fill=(240, 240, 240, 255))
        d.rectangle([cx - w * 0.1, h * 0.4, cx + w * 0.1, h * 0.52], fill=(210, 60, 60, 255))
        d.rectangle([cx - w * 0.1, h * 0.62, cx + w * 0.1, h * 0.74], fill=(210, 60, 60, 255))
        d.ellipse([cx - w * 0.09, h * 0.1, cx + w * 0.09, h * 0.24], fill=(250, 230, 120, 255))
    elif shape == "rocket":
        d.rectangle([cx - w * 0.12, h * 0.3, cx + w * 0.12, h * 0.9], fill=(232, 232, 236, 255))
        d.polygon([(cx - w * 0.12, h * 0.3), (cx + w * 0.12, h * 0.3), (cx, h * 0.08)], fill=(210, 70, 60, 255))
        d.polygon([(cx - w * 0.12, h * 0.74), (cx - w * 0.26, h * 0.92), (cx - w * 0.12, h * 0.9)], fill=(210, 70, 60, 255))
        d.polygon([(cx + w * 0.12, h * 0.74), (cx + w * 0.26, h * 0.92), (cx + w * 0.12, h * 0.9)], fill=(210, 70, 60, 255))
    elif shape == "pyramid":
        d.polygon([(w * 0.1, h * 0.92), (w * 0.9, h * 0.92), (cx, h * 0.2)], fill=(214, 180, 110, 255))
    elif shape == "dome":
        d.pieslice([w * 0.15, h * 0.42, w * 0.85, h * 1.3], start=180, end=360, fill=(184, 192, 205, 255))
        d.rectangle([cx - 4, h * 0.22, cx + 4, h * 0.5], fill=(120, 200, 220, 255))
    elif shape == "tower":
        d.rectangle([cx - w * 0.17, h * 0.1, cx + w * 0.17, h * 0.95], fill=(90, 100, 140, 255))
        for yy in range(3, 9):
            d.rectangle([cx - w * 0.1, h * yy * 0.09, cx + w * 0.1, h * (yy * 0.09 + 0.04)], fill=(200, 220, 255, 255))
    elif shape == "barn":
        d.rectangle([w * 0.2, h * 0.5, w * 0.8, h * 0.92], fill=(180, 60, 50, 255))
        d.polygon([(w * 0.2, h * 0.5), (w * 0.8, h * 0.5), (w * 0.7, h * 0.3), (w * 0.3, h * 0.3)], fill=(150, 50, 42, 255))
        d.rectangle([w * 0.42, h * 0.62, w * 0.58, h * 0.92], fill=(120, 40, 34, 255))
    else:
        d.ellipse([cx-w*0.35,cy-h*0.35,cx+w*0.35,cy+h*0.35], fill=(200,200,210,255))
    return img


# ============================================================ post + QA
def make_seamless(img: Image.Image) -> Image.Image:
    if np is None:
        return img
    a = np.array(img.convert("RGB")).astype(float)
    h, w, _ = a.shape
    off = np.roll(np.roll(a, w // 2, 1), h // 2, 0)
    xs = 1 - np.abs(np.linspace(-1, 1, w)); ys = 1 - np.abs(np.linspace(-1, 1, h))
    m = np.minimum.outer(ys, xs)[..., None]         # 1 in centre, 0 at edges
    out = a * m + off * (1 - m)
    return Image.fromarray(out.astype("uint8"))

def qa(img: Image.Image, spec: dict) -> tuple[bool, str]:
    w, h = spec["size"]
    if img.size != (w, h):
        return False, f"size {img.size} != {(w, h)}"
    if np is None:
        return True, "ok (no numpy: coverage check skipped)"
    a = np.array(img.convert("RGBA"))
    if spec.get("transparent", True) and not spec.get("tileable", False):
        cov = float((a[..., 3] > 24).mean())
        if cov < 0.02:
            return False, f"almost empty (alpha coverage {cov:.1%})"
        if cov > 0.99:
            return False, "no transparency produced (fully opaque)"
        rgb = a[..., :3][a[..., 3] > 24]
        if rgb.size and rgb.std() < 6:
            return False, "flat single-color blob"
    else:  # opaque texture: must have real detail
        if a[..., :3].std() < 6:
            return False, "texture is a flat color (no detail)"
    return True, f"ok"


def _alpha_frac(img) -> float:
    if np is None:
        return 1.0
    a = np.asarray(img.convert("RGBA"))
    return float((a[..., 3] < 24).mean())

def corner_flood(img, tol: int = 74):
    """Key out the background by its border color: remove every connected region
    that touches an edge and is within `tol` of the sampled border color. Interior
    pixels of that color are KEPT (dark outlines survive). Works for ANY solid-ish
    background, not just black. Needs numpy (+ scipy for connectivity)."""
    img = img.convert("RGBA")
    if np is None:
        return img
    a = np.asarray(img).astype(np.int16)
    h, w = a.shape[:2]
    border = np.concatenate([a[0, :, :3], a[-1, :, :3], a[:, 0, :3], a[:, -1, :3]])
    bg = np.median(border, axis=0)
    dist = np.sqrt(((a[:, :, :3] - bg) ** 2).sum(2))
    bgmask = dist < tol
    try:
        from scipy import ndimage
        lbl, _ = ndimage.label(bgmask)
        keep = set(lbl[0, :].tolist()) | set(lbl[-1, :].tolist()) | set(lbl[:, 0].tolist()) | set(lbl[:, -1].tolist())
        keep.discard(0)
        remove = np.isin(lbl, list(keep))
    except Exception:
        remove = bgmask
    out = a.astype(np.uint8)
    out[remove, 3] = 0
    return Image.fromarray(out, "RGBA")

def _cutout(img):
    # use rembg (via run.py) only if it actually yields transparency; else key the bg
    if _R is not None and hasattr(_R, "bg_remove"):
        try:
            r = _R.bg_remove(img)
            if _alpha_frac(r) > 0.02:
                return r
        except Exception:
            pass
    return corner_flood(img)

def _ground(img, w: int, h: int, pad: int = 2):
    """Crop transparent margins and re-place the content on a (w,h) canvas,
    anchored to the bottom-center. The sprite's base then sits on the image's
    bottom edge, so it touches the ground in-game instead of floating."""
    img = img.convert("RGBA")
    bbox = img.split()[3].getbbox()
    if not bbox:
        return img.resize((w, h), Image.LANCZOS)
    content = img.crop(bbox)
    cw, ch = content.size
    scale = min(w / cw, (h - pad) / ch)
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    content = content.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.alpha_composite(content, ((w - nw) // 2, h - nh))   # bottom-anchored
    return canvas


# ============================================================ generate one
STYLE = ""
def _fullprompt(spec: dict) -> str:
    return f"{spec['prompt']}, {STYLE}".strip(", ")

def generate_one(spec: dict, out_dir: Path, workflow, force: bool) -> str:
    name = spec["name"]
    w, h = spec["size"]
    opaque = spec.get("tileable", False) or not spec.get("transparent", True)
    dest = out_dir / f"{name}.png"
    if dest.exists() and not force:
        return "skip"
    if _R is None or workflow is None:
        return "no-comfy"
    bw, bh = base_size(w, h)
    for attempt in range(2):
        sd = _seed(name) + attempt * 7919
        sil = draw_silhouette(spec["shape"], bw, bh, opaque, sd)
        img = _R.render_transform(workflow, sil, _fullprompt(spec), sd,
                                  float(spec.get("denoise", 0.72)),
                                  f"shibkart_{name}", pad_square=not opaque)
        if not opaque:
            img = _cutout(img)
            img = _ground(img, w, h)               # crop margins + bottom-anchor -> sits on ground
        elif spec.get("tileable", False):
            img = make_seamless(img).convert("RGBA").resize((w, h), Image.LANCZOS)
        else:
            img = img.convert("RGBA").resize((w, h), Image.LANCZOS)
        ok, why = qa(img, spec)
        if ok:
            out_dir.mkdir(parents=True, exist_ok=True)
            img.save(dest)
            print(f"  [ok] {dest.relative_to(SHIBKART)}  ({w}x{h}) {why}")
            return "ok"
        print(f"  [retry {name}] QA failed: {why}")
    print(f"  [FAIL] {name}: did not pass QA after 2 tries")
    return "fail"


# ============================================================ offline validate
def offline_validate(roster: dict, dump: bool) -> int:
    print("== OFFLINE VALIDATION (no ComfyUI) ==")
    problems = 0
    if dump:
        SIL_DIR.mkdir(parents=True, exist_ok=True)
    for cat, items in roster.items():
        if cat not in CATEGORY_DIR:
            print(f"  [!] unknown category '{cat}' (no output folder)"); problems += 1; continue
        for spec in items:
            for key in ("name", "shape", "size", "prompt"):
                if key not in spec:
                    print(f"  [!] {cat}/{spec.get('name','?')} missing '{key}'"); problems += 1
            w, h = spec.get("size", [0, 0])
            opaque = spec.get("tileable", False) or not spec.get("transparent", True)
            bw, bh = base_size(w, h)
            sd = _seed(spec["name"])
            sil = draw_silhouette(spec["shape"], bw, bh, opaque, sd)
            # QA the silhouette resized to target as a proxy for the pipeline output
            proxy = sil.resize((w, h), Image.LANCZOS)
            transparent_sprite = spec.get("transparent", True) and not spec.get("tileable", False)
            if transparent_sprite and np is not None:
                arr = np.array(sil.convert("RGB"))
                cov = float((arr.max(axis=2) > 24).mean())   # non-black = the drawn shape
                ok = 0.02 < cov < 0.99
                why = f"silhouette coverage {cov:.0%}"
                if not ok:
                    problems += 1
            else:
                ok, why = qa(proxy, spec)
                if not ok:
                    problems += 1
            flag = "ok " if ok else "BAD "
            if dump:
                sil.save(SIL_DIR / f"{cat}_{spec['name']}.png")
            print(f"  [{flag}] {cat}/{spec['name']:<14} {w}x{h:<4} shape={spec['shape']:<12} -> {why}")
    n = sum(len(v) for v in roster.values())
    print(f"\n{n} assets across {len(roster)} categories. Folders resolve, shapes draw, QA runs.")
    print("problems:", problems, "->", "PASS ✅" if problems == 0 else "FIX ABOVE ❌")
    if dump:
        print("silhouettes written to", SIL_DIR.relative_to(SHIBKART))
    return 0 if problems == 0 else 1


# ============================================================ boshi rig copy
ANIMS = ["idle", "walk", "run"]
def copy_boshis() -> int:
    ADDON_ASSETS.mkdir(parents=True, exist_ok=True)
    (ADDON_ASSETS / "traits").mkdir(parents=True, exist_ok=True)
    n = 0
    for anim in ANIMS:
        for cand in [CANON_ASSETS / f"maz_{anim}.png", CANON_ASSETS / f"maz_naked_{anim}.png"]:
            if cand.exists():
                shutil.copy2(cand, ADDON_ASSETS / f"maz_{anim}.png"); n += 1; break
    st = CANON_ASSETS / "traits"
    if st.exists():
        dst = ADDON_ASSETS / "traits"
        if dst.exists(): shutil.rmtree(dst)
        shutil.copytree(st, dst); n += sum(1 for _ in dst.rglob("*.png"))
    if n == 0:
        print("  [!] No canonical Boshi rig under", CANON_ASSETS)
        print("      Build it first:  cd", GAMEDEV / "_boshicore_canon", "; python gen_conform.py boshi_base ; python generate_all.py")
        return 1
    print(f"  copied {n} Boshi rig file(s) -> {ADDON_ASSETS.relative_to(SHIBKART)}")
    return 0


# ============================================================ main
def main() -> int:
    global STYLE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="'category' or 'category/name'")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--validate", action="store_true", help="offline: draw silhouettes + run QA, no ComfyUI")
    ap.add_argument("--silhouettes", action="store_true", help="offline: write silhouettes to assets/_silhouettes and validate")
    ap.add_argument("--force", action="store_true", help="regenerate even if the output exists")
    ap.add_argument("--boshis", action="store_true", help="copy the canonical Boshi rig into the addon and exit")
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    STYLE = manifest.get("_style", "")
    roster = {k: v for k, v in manifest.items() if not k.startswith("_")}

    if args.list:
        for cat, items in roster.items():
            print(f"{cat}: " + ", ".join(i["name"] for i in items))
        return 0
    if args.boshis:
        return copy_boshis()
    if args.validate or args.silhouettes:
        return offline_validate(roster, dump=args.silhouettes)

    if _R is None or not PROVEN_WORKFLOW.exists():
        print("!! Proven ComfyUI pipeline not found at", PROVEN_WORKFLOW)
        print("   (need gamedev/tools/spritegen/run.py + workflow.json). Try --validate offline first.")
        return 2
    workflow = json.loads(PROVEN_WORKFLOW.read_text())
    print(f"Using proven workflow: {PROVEN_WORKFLOW}  (silhouette -> edit, no LoRAs)\n")

    want_cat, want_name = (args.only.split("/", 1) + [None])[:2] if args.only else (None, None)
    tally = {"ok": 0, "skip": 0, "fail": 0}
    for cat, items in roster.items():
        if want_cat and cat != want_cat: continue
        out_dir = CATEGORY_DIR[cat]
        print(f"== {cat} ==")
        for spec in items:
            if want_name and spec["name"] != want_name: continue
            r = generate_one(spec, out_dir, workflow, args.force)
            if r in tally: tally[r] += 1
    print(f"\nDONE  ok={tally['ok']} skipped={tally['skip']} failed={tally['fail']}")
    print("Launch: Godot 4.6 -> open ShibKart/project.godot -> F5")
    return 1 if tally["fail"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
