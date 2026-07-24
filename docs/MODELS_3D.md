# ShibKart — 3D models (Hunyuan3D)

Reuses maz's **proven ShibTown3D comfy3d pipeline** (copied verbatim into
`tools/comfy3d/`, ShibTown3D left untouched). Two stages, wired to this machine's
ComfyUI: Qwen-Image concept → Hunyuan3D-2.2 mesh.

```
prompt ──(Qwen-Image GGUF + 4-step Lightning)──► concept PNG ──(Hunyuan 3D 2.2 Remesh)──► <name>.glb
```

## Run (from ShibKart-web)
```
# Stage 1 — concept images
python tools/comfy3d/gen_images.py
#   review tools/comfy3d/out/concept/, rename the best variation of each to <name>.png

# Stage 2 — meshes through your "Hunyuan 3D 2.2 Remesh" workflow
python tools/comfy3d/gen_3d.py
#   GLBs land in public/models/<name>.glb — the game auto-loads them
```
Handy: `--only kart_standard kart_sport`, `--dry-run`, `--batch 6`.

## Asset list — `tools/comfy3d/prompts.json`
Names match exactly what the game loads:
- **Karts:** `kart_standard`, `kart_sport`, `kart_heavy` → the 3 bodies (drivers seated on top).
- **Props:** `item_box`, `boost_pad`, `tree_round`, `cactus`, `rock`, `sponsor_stand`,
  `start_arch`, `tire_stack`, `coin`, `palm`, `snowman`.

## How the game consumes them
`src/game/models.ts` `loadModel(name)` loads `public/models/<name>.glb`, auto-scales
it and drops it on the ground; **procedural fallback** if the file's absent, so
everything renders before any model exists. Karts already prefer the `.glb`.

## Nothing to set up
The scripts default to maz's existing ComfyUI models
(`qwen-image-2512-Q8_0.gguf` + `Qwen-Image-2512-Lightning-4steps` LoRA) and the
saved workflow `…/workflows/Hunyuan 3D 2.2 Remesh.json` — all already installed.
Point elsewhere with `--workflow <file>` / `--unet` flags if needed.

The **Boshi driver** stays on the BoshiCore rig (`public/boshi/base.glb`) — Hunyuan3D
is for karts/props only.
