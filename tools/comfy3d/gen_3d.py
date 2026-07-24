#!/usr/bin/env python3
"""ShibTown3D - STEP 2: images -> 3D meshes.

Feeds each concept PNG through YOUR Hunyuan3D workflow
("Hunyuan 3D 2.2 Remesh.json") and saves a textured GLB per image.

It loads your saved UI workflow, converts it to an API graph on the fly
(resolving the Set/Get nodes), then for every image just swaps the LoadImage
input and the export filename - all your tuned settings are preserved.

Output -> out/models/<name>.glb, and each GLB is also copied into
../../assets/models/ so it's ready to drop into the game.

Usage:
    python gen_3d.py                         # every image in out/concept/
    python gen_3d.py --input path/to/pngs
    python gen_3d.py --only windmill well
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

from comfy_client import ComfyClient
import ui2api

HERE = Path(__file__).resolve().parent
DEFAULT_INPUT = HERE / "out" / "concept"
MODEL_DIR = HERE / "out" / "models"
GAME_MODELS = (HERE / ".." / ".." / "public" / "models").resolve()

DEFAULT_WORKFLOW = Path(
    r"C:\AIVIDS\ComfyUI-Easy-Install-Windows\ComfyUI-Easy-Install\ComfyUI"
    r"\user\default\workflows\Hunyuan 3D 2.2 Remesh.json")

IMG_EXTS = {".png", ".jpg", ".jpeg", ".webp"}


import re
_VARIATION = re.compile(r"_\d+$")   # e.g. windmill_2 (a raw variation, not a pick)


def collect_images(input_dir: Path, only, include_variations=False):
    imgs = sorted(p for p in input_dir.iterdir() if p.suffix.lower() in IMG_EXTS)
    if only:
        keep = set(only)
        imgs = [p for p in imgs if p.stem in keep]
    elif not include_variations:
        # default: one pick per asset (base <name>.png), skip _1/_2/_3 variations
        imgs = [p for p in imgs if not _VARIATION.search(p.stem)]
    return imgs


def scan_meshes(entry: dict):
    """Yield (filename, subfolder, type) for every .glb/.obj/.ply referenced in a
    history entry - as file-dicts OR as bare path strings (Hy3DExportMesh)."""
    exts = (".glb", ".obj", ".ply")
    found = []

    def walk(v):
        if isinstance(v, dict):
            if "filename" in v and str(v["filename"]).lower().endswith(exts):
                found.append((v["filename"], v.get("subfolder", ""), v.get("type", "output")))
            else:
                for x in v.values():
                    walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, str) and v.lower().endswith(exts):
            p = v.replace("\\", "/").lstrip("/")
            sub, _, name = p.rpartition("/")
            found.append((name, sub, "output"))

    walk(entry.get("outputs", {}))
    # de-dup, keep last (usually the final exported mesh)
    seen, out = set(), []
    for f in found:
        if f not in seen:
            seen.add(f); out.append(f)
    return out


def strip_texture_branch(api: dict, export_id: str):
    """Repoint the exporter to the pre-texture mesh and drop every node that
    isn't needed to produce it. Removes the render/bake/apply-texture nodes, so
    the compiled 'custom_rasterizer' extension is never imported."""
    geom = (ui2api.find_node(api, "MeshUVWrap", "UVWrap")
            or ui2api.find_node(api, "Remesh")
            or ui2api.find_node(api, "Postprocess")
            or ui2api.find_node(api, "VAEDecode"))
    if not geom:
        sys.exit("[3d] --no-texture: couldn't find a pre-texture mesh node to export.")
    # the exporter's mesh input is its only list-valued (connection) input
    mesh_key = next((k for k, v in api[export_id]["inputs"].items() if isinstance(v, list)), None)
    if mesh_key:
        api[export_id]["inputs"][mesh_key] = [geom, 0]

    # keep only nodes reachable from the exporter
    keep, stack = set(), [export_id]
    while stack:
        nid = stack.pop()
        if nid in keep or nid not in api:
            continue
        keep.add(nid)
        for v in api[nid]["inputs"].values():
            if isinstance(v, list) and len(v) == 2 and isinstance(v[0], str):
                stack.append(v[0])
    return {nid: node for nid, node in api.items() if nid in keep}, geom


def main():
    ap = argparse.ArgumentParser(description="ShibTown3D image->mesh via your Hunyuan3D workflow")
    ap.add_argument("--input", default=str(DEFAULT_INPUT), help="folder of concept PNGs")
    ap.add_argument("--only", nargs="*", help="only images whose name matches these")
    ap.add_argument("--all-variations", action="store_true",
                    help="also process _1/_2/_3 variation images (default: one pick per asset)")
    ap.add_argument("--skip-existing", action="store_true",
                    help="skip images whose assets/models/<name>.glb already exists (only new meshes)")
    ap.add_argument("--workflow", default=str(DEFAULT_WORKFLOW))
    ap.add_argument("--comfy-root", default=str(DEFAULT_WORKFLOW.parents[3]),
                    help="ComfyUI root, used to read the exported GLB off disk")
    ap.add_argument("--url", default="http://127.0.0.1:8188")
    ap.add_argument("--dry-run", action="store_true", help="convert + print graph, don't run")
    ap.add_argument("--no-texture", action="store_true",
                    help="export untextured geometry; skips the texture branch so "
                         "custom_rasterizer / GPU-rasterizer deps are never loaded")
    args = ap.parse_args()

    wf_path = Path(args.workflow)
    if not wf_path.exists():
        sys.exit(f"[3d] workflow not found: {wf_path}")
    ui = json.loads(wf_path.read_text(encoding="utf-8"))
    if "nodes" not in ui:
        sys.exit("[3d] that file isn't a UI workflow (no 'nodes'). Point --workflow at the .json you save from the ComfyUI canvas.")

    input_dir = Path(args.input)
    if not input_dir.exists():
        sys.exit(f"[3d] input folder not found: {input_dir}")
    images = collect_images(input_dir, args.only, args.all_variations)
    if args.skip_existing:
        images = [p for p in images if not (GAME_MODELS / f"{p.stem}.glb").exists()]
    if not images:
        sys.exit(f"[3d] no images in {input_dir} "
                 f"(run gen_images.py, then rename the best of each to <name>.png).")

    client = ComfyClient(args.url, timeout=1800)
    if not client.ping():
        sys.exit(f"[3d] can't reach ComfyUI at {args.url} - start it first.")

    print("[3d] converting your workflow to API graph ...")
    api = ui2api.convert(ui, ui2api.fetch_object_info(args.url))
    load_id = ui2api.find_node(api, "LoadImage")
    export_id = ui2api.find_node(api, "Hy3DExportMesh", "ExportMesh", "SaveGLB")
    if not load_id or not export_id:
        sys.exit(f"[3d] couldn't locate LoadImage ({load_id}) / export ({export_id}) in the graph.")
    if args.no_texture:
        api, geom = strip_texture_branch(api, export_id)
        print(f"[3d] no-texture mode: exporting geometry from node {geom} "
              f"({len(api)} nodes, texture branch removed).")
    print(f"[3d] LoadImage=node {load_id}, export=node {export_id}. {len(images)} image(s).")

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    GAME_MODELS.mkdir(parents=True, exist_ok=True)
    ok = 0
    failed = []
    for img in images:
        name = img.stem
        graph = json.loads(json.dumps(api))
        graph[load_id]["inputs"]["image"] = None  # set below after upload
        graph[export_id]["inputs"]["filename_prefix"] = f"shibtown3d/{name}"
        if args.dry_run:
            graph[load_id]["inputs"]["image"] = f"shibtown3d/{img.name}"
            print(f"\n=== {name} ===\n{json.dumps(graph, indent=2)[:2000]} ...")
            continue
        print(f"[3d] {name}: uploading + generating (this takes a while) ...", flush=True)
        try:
            graph[load_id]["inputs"]["image"] = client.upload_image(img)
            entry = client.wait(client.submit(graph))
        except Exception as e:
            msg = str(e).splitlines()[0][:120] if str(e) else e.__class__.__name__
            # surface the ComfyUI node/exception if present
            for key in ("node_type", "exception_message"):
                if key in str(e):
                    import re as _re
                    m = _re.search(rf'"{key}":\s*"([^"]+)"', str(e))
                    if m:
                        msg = m.group(1).strip()
            print(f"      ! FAILED ({msg}) - skipping, continuing batch")
            failed.append(name)
            continue

        out = MODEL_DIR / f"{name}.glb"
        saved = False

        # 1) preferred: read the freshly-written GLB straight off ComfyUI's disk
        comfy_out = Path(args.comfy_root) / "output" / "shibtown3d"
        if comfy_out.exists():
            cands = sorted(comfy_out.glob(f"{name}_*.glb"), key=lambda p: p.stat().st_mtime)
            cands += sorted(comfy_out.glob(f"{name}.glb"), key=lambda p: p.stat().st_mtime)
            if cands:
                shutil.copy2(cands[-1], out)
                saved = True

        # 2) fallback: pull it from the API response via /view
        if not saved:
            for fname, sub, ftype in scan_meshes(entry):
                if fname.lower().endswith(".glb"):
                    out.write_bytes(client._view(fname, sub, ftype))
                    saved = True
                    break

        if saved:
            shutil.copy2(out, GAME_MODELS / out.name)
            print(f"      -> {out.name}  (copied to assets/models/)")
            ok += 1
        else:
            print(f"      ! no GLB found - check {args.comfy_root}\\output\\shibtown3d\\")
            failed.append(name)

    if not args.dry_run:
        print(f"\n[3d] done: {ok}/{len(images)} meshes in assets/models/")
        if failed:
            print(f"[3d] {len(failed)} failed (usually the remesh step on tricky geometry): "
                  f"{', '.join(failed)}")
            print("     Retry them with a different concept variation, e.g. rename")
            print("     out/concept/<name>_2.png -> <name>.png, then rerun --skip-existing.")


if __name__ == "__main__":
    main()
