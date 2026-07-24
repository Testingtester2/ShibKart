#!/usr/bin/env python3
"""ShibTown3D - STEP 1: concept images.

Generates a clean, single-object concept PNG for every world asset in
prompts.json, using this machine's Qwen-Image (GGUF) + 4-step Lightning LoRA
stack. Output -> out/concept/<name>_00.png ... (one per variation).

Then eyeball out/concept/, pick the best variation of each asset, and rename the
winner to <name>.png  (that's what gen_3d.py consumes).

Usage:
    python gen_images.py                      # all assets, 4 variations each
    python gen_images.py --only windmill well
    python gen_images.py --batch 6 --width 1024 --height 1024
    python gen_images.py --dry-run --only windmill
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

from comfy_client import ComfyClient

HERE = Path(__file__).resolve().parent
CONCEPT_DIR = HERE / "out" / "concept"

# Verified present in the user's ComfyUI (override with flags if needed).
QWEN_UNET = "qwen-image-2512-Q8_0.gguf"
QWEN_CLIP = "qwen_2.5_vl_7b_fp8_scaled.safetensors"
QWEN_VAE = "qwen_image_vae.safetensors"
QWEN_LIGHTNING = "Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors"


def build_graph(prompt, name, args):
    seed = args.seed if args.seed >= 0 else random.randint(0, 2**31 - 1)
    return {
        "unet": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": args.unet}},
        "clip": {"class_type": "CLIPLoader",
                 "inputs": {"clip_name": args.clip, "type": "qwen_image", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": args.vae}},
        "lora": {"class_type": "LoraLoaderModelOnly",
                 "inputs": {"model": ["unet", 0], "lora_name": args.lightning,
                            "strength_model": 1.0}},
        "sampling": {"class_type": "ModelSamplingAuraFlow",
                     "inputs": {"model": ["lora", 0], "shift": 3.1}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": prompt}},
        "neg": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": ""}},
        "latent": {"class_type": "EmptySD3LatentImage",
                   "inputs": {"width": args.width, "height": args.height, "batch_size": args.batch}},
        "ksampler": {"class_type": "KSampler",
                     "inputs": {"seed": seed, "steps": 4, "cfg": 1.0, "sampler_name": "euler",
                                "scheduler": "simple", "denoise": 1.0, "model": ["sampling", 0],
                                "positive": ["pos", 0], "negative": ["neg", 0],
                                "latent_image": ["latent", 0]}},
        "decode": {"class_type": "VAEDecode", "inputs": {"samples": ["ksampler", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveImage",
                 "inputs": {"filename_prefix": f"shibkart/{name}", "images": ["decode", 0]}},
    }


def main():
    ap = argparse.ArgumentParser(description="ShibTown3D concept-image generator (Qwen-Image)")
    ap.add_argument("--only", nargs="*", help="only these asset names")
    ap.add_argument("--skip-existing", action="store_true",
                    help="skip assets that already have out/concept/<name>.png (generate only new ones)")
    ap.add_argument("--batch", type=int, default=4, help="variations per asset")
    ap.add_argument("--width", type=int, default=1024)
    ap.add_argument("--height", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--url", default="http://127.0.0.1:8188")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--unet", default=QWEN_UNET)
    ap.add_argument("--clip", default=QWEN_CLIP)
    ap.add_argument("--vae", default=QWEN_VAE)
    ap.add_argument("--lightning", default=QWEN_LIGHTNING)
    args = ap.parse_args()

    data = json.loads((HERE / "prompts.json").read_text(encoding="utf-8"))
    suffix, assets = data["style_suffix"], data["assets"]
    if args.only:
        keep = set(args.only)
        assets = [a for a in assets if a["name"] in keep]
        if not assets:
            sys.exit(f"[img] no matching assets in {sorted(keep)}")
    if args.skip_existing:
        assets = [a for a in assets if not (CONCEPT_DIR / f"{a['name']}.png").exists()]
        if not assets:
            sys.exit("[img] nothing new - every asset already has a concept image.")

    client = ComfyClient(args.url)
    if not args.dry_run and not client.ping():
        sys.exit(f"[img] can't reach ComfyUI at {args.url} - start it first (or --dry-run).")

    CONCEPT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[img] {len(assets)} assets x {args.batch} variations -> {CONCEPT_DIR}")
    for a in assets:
        graph = build_graph(f"{a['prompt']}, {suffix}", a["name"], args)
        if args.dry_run:
            print(f"\n=== {a['name']} ===\n{json.dumps(graph, indent=2)}")
            continue
        print(f"[img] {a['name']} ...", flush=True)
        entry = client.wait(client.submit(graph))
        saved = client.download_outputs(entry, CONCEPT_DIR, a["name"], extensions=(".png",))
        print(f"      -> {', '.join(p.name for p in saved) or 'no image returned'}")

    if not args.dry_run:
        print("\nNext: review out/concept/, rename the best variation of each asset to")
        print("      <name>.png, then run:  python gen_3d.py")


if __name__ == "__main__":
    main()
