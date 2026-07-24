#!/usr/bin/env python3
"""Master ShibKart-web asset generator — runs ALL generators.

  python tools/gen_all.py --validate    # offline check of everything
  python tools/gen_all.py --skybox       # just free procedural skyboxes (no ComfyUI)
  python tools/gen_all.py                # logos + menu + world art (no LoRA)

Requires ComfyUI running for the diffusion art (skyboxes are procedural, always work).
"""
import sys, subprocess
from pathlib import Path
HERE = Path(__file__).resolve().parent
args = sys.argv[1:]
gens = ["gen_menu_assets.py", "gen_world_assets.py"]
rc = 0
for g in gens:
    print(f"\n===== {g} =====")
    rc |= subprocess.call([sys.executable, str(HERE / g), *args])
print("\n===== gen_all done =====")
sys.exit(0 if "--validate" in args else rc)
