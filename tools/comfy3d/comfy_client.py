#!/usr/bin/env python3
"""Minimal ComfyUI HTTP client for the ShibTown3D asset pipeline.

No websocket dependency - it just submits a prompt graph and polls /history.
Handles image upload (for image->3D), job submission, progress polling, and
downloading result files (PNG concept images and GLB/OBJ meshes) via /view.

Works with any ComfyUI instance; default http://127.0.0.1:8188.
"""
from __future__ import annotations

import json
import time
import uuid
from pathlib import Path

import requests


class ComfyClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8188", timeout: int = 600):
        self.base = base_url.rstrip("/")
        self.timeout = timeout
        self.client_id = str(uuid.uuid4())

    # ---- connectivity --------------------------------------------------------
    def ping(self) -> bool:
        try:
            requests.get(f"{self.base}/system_stats", timeout=5).raise_for_status()
            return True
        except Exception:
            return False

    # ---- inputs --------------------------------------------------------------
    def upload_image(self, path: Path, subfolder: str = "shibtown3d") -> str:
        """Upload an image into ComfyUI's input dir; returns the name to feed a
        LoadImage node (as 'subfolder/name' when a subfolder is used)."""
        path = Path(path)
        with open(path, "rb") as fh:
            files = {"image": (path.name, fh, "image/png")}
            data = {"overwrite": "true", "subfolder": subfolder}
            r = requests.post(f"{self.base}/upload/image", files=files, data=data, timeout=60)
        r.raise_for_status()
        info = r.json()
        sub = info.get("subfolder", "")
        name = info["name"]
        return f"{sub}/{name}" if sub else name

    # ---- jobs ----------------------------------------------------------------
    def submit(self, graph: dict) -> str:
        payload = {"prompt": graph, "client_id": self.client_id}
        r = requests.post(f"{self.base}/prompt", json=payload, timeout=60)
        if r.status_code != 200:
            raise RuntimeError(f"ComfyUI rejected the graph ({r.status_code}):\n{r.text}")
        return r.json()["prompt_id"]

    def wait(self, prompt_id: str, poll: float = 1.5) -> dict:
        """Block until the prompt finishes; returns its history entry."""
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            r = requests.get(f"{self.base}/history/{prompt_id}", timeout=30)
            r.raise_for_status()
            hist = r.json()
            if prompt_id in hist:
                entry = hist[prompt_id]
                status = entry.get("status", {})
                if status.get("completed") or "outputs" in entry:
                    if status.get("status_str") == "error":
                        raise RuntimeError(f"ComfyUI job errored: {json.dumps(status, indent=2)}")
                    return entry
            time.sleep(poll)
        raise TimeoutError(f"Job {prompt_id} did not finish within {self.timeout}s")

    # ---- outputs -------------------------------------------------------------
    def download_outputs(self, entry: dict, dest_dir: Path, base_name: str,
                         extensions=(".glb", ".obj", ".ply", ".png")) -> list[Path]:
        """Pull every produced file matching `extensions` out of a history entry."""
        dest_dir = Path(dest_dir)
        dest_dir.mkdir(parents=True, exist_ok=True)
        saved: list[Path] = []
        outputs = entry.get("outputs", {})
        idx = 0
        for _node_id, node_out in outputs.items():
            for key, value in node_out.items():
                for fileinfo in _iter_fileinfos(value):
                    fname = fileinfo.get("filename", "")
                    if not fname.lower().endswith(extensions):
                        continue
                    data = self._view(fname, fileinfo.get("subfolder", ""),
                                      fileinfo.get("type", "output"))
                    ext = Path(fname).suffix
                    suffix = "" if idx == 0 else f"_{idx}"
                    out = dest_dir / f"{base_name}{suffix}{ext}"
                    out.write_bytes(data)
                    saved.append(out)
                    idx += 1
        return saved

    def _view(self, filename: str, subfolder: str, ftype: str) -> bytes:
        params = {"filename": filename, "subfolder": subfolder, "type": ftype}
        r = requests.get(f"{self.base}/view", params=params, timeout=120)
        r.raise_for_status()
        return r.content


def _iter_fileinfos(value):
    """History output values can be lists of {filename,subfolder,type} dicts,
    or nested. Yield every dict that looks like a file descriptor."""
    if isinstance(value, dict):
        if "filename" in value:
            yield value
        else:
            for v in value.values():
                yield from _iter_fileinfos(v)
    elif isinstance(value, list):
        for v in value:
            yield from _iter_fileinfos(v)
