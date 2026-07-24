#!/usr/bin/env python3
"""Convert a ComfyUI *UI* workflow (the .json saved from the canvas, with
"nodes"/"links") into an *API* prompt graph the /prompt endpoint can run.

Robust to version drift between the saved workflow and the installed nodes:
  - connection inputs are matched **positionally** (survives input renames,
    e.g. an older 'mesh' slot feeding a node that now calls it 'trimesh')
  - missing widget values are filled from each node's **schema default**
    (covers newly-added required widgets like 'file_format')
  - resolves rgthree/kjnodes **Set/Get** virtual nodes and **Reroute**
  - drops **Note / MarkdownNote**
  - swallows the hidden **control_after_generate** value after a seed

Requires a running ComfyUI (for /object_info). Used by gen_3d.py.
"""
from __future__ import annotations

import requests

DROP = {"Note", "MarkdownNote"}
VIRTUAL = {"SetNode", "GetNode", "Reroute"}
WIDGET_SCALARS = {"INT", "FLOAT", "STRING", "BOOLEAN"}
CONTROL_WORDS = {"fixed", "increment", "decrement", "randomize"}


def fetch_object_info(base_url: str) -> dict:
    r = requests.get(f"{base_url.rstrip('/')}/object_info", timeout=60)
    r.raise_for_status()
    return r.json()


def _is_widget(itype) -> bool:
    return isinstance(itype, list) or itype in WIDGET_SCALARS


def _widget_default(spec):
    # spec is [type, opts] (opts optional). combos: type is a list of choices.
    if isinstance(spec, (list, tuple)) and spec:
        itype = spec[0]
        opts = spec[1] if len(spec) > 1 and isinstance(spec[1], dict) else {}
        if "default" in opts:
            return opts["default"]
        if isinstance(itype, list) and itype:      # combo -> first choice
            return itype[0]
        if itype == "BOOLEAN":
            return False
        if itype == "INT":
            return 0
        if itype == "FLOAT":
            return 0.0
        if itype == "STRING":
            return ""
    return None


def convert(ui: dict, object_info: dict) -> dict:
    nodes = {n["id"]: n for n in ui["nodes"]}
    linkmap = {l[0]: (l[1], l[2]) for l in ui["links"]}  # link_id -> (from_node, from_slot)

    set_raw = {}
    for n in ui["nodes"]:
        if n["type"] == "SetNode" and n.get("inputs"):
            link = n["inputs"][0].get("link")
            if link is not None:
                set_raw[n["widgets_values"][0]] = linkmap[link]

    def resolve(node_id, slot, seen=None):
        seen = (seen or set())
        if node_id in seen:
            raise ValueError(f"virtual-node cycle at {node_id}")
        seen = seen | {node_id}
        n = nodes[node_id]
        t = n["type"]
        if t == "Reroute":
            return resolve(*linkmap[n["inputs"][0]["link"]], seen)
        if t == "GetNode":
            return resolve(*set_raw[n["widgets_values"][0]], seen)
        if t == "SetNode":
            return resolve(*linkmap[n["inputs"][0]["link"]], seen)
        return (node_id, slot)

    api = {}
    for n in ui["nodes"]:
        t = n["type"]
        if t in DROP or t in VIRTUAL:
            continue
        info = object_info.get(t)
        if not info:
            raise SystemExit(
                f"[ui2api] ComfyUI doesn't know node '{t}' - is that custom node installed?")
        spec = info["input"]
        ordered = list(spec.get("required", {}).items()) + list(spec.get("optional", {}).items())
        conn_defs = [(nm, sp) for nm, sp in ordered if not _is_widget(sp[0] if isinstance(sp, (list, tuple)) and sp else sp)]
        widget_defs = [(nm, sp) for nm, sp in ordered if _is_widget(sp[0] if isinstance(sp, (list, tuple)) and sp else sp)]

        ui_slots = n.get("inputs", []) or []          # ordered connection slots on the canvas
        wq = list(n.get("widgets_values") or [])
        inputs = {}

        # connection inputs, matched by position (robust to renames)
        for idx, (name, _sp) in enumerate(conn_defs):
            if idx < len(ui_slots) and ui_slots[idx].get("link") is not None:
                rn, rs = resolve(*linkmap[ui_slots[idx]["link"]])
                inputs[name] = [str(rn), rs]

        # widget inputs, consumed in order; fall back to schema default
        for name, sp in widget_defs:
            itype = sp[0] if isinstance(sp, (list, tuple)) and sp else sp
            if wq:
                val = wq.pop(0)
                if itype == "INT" and wq and isinstance(wq[0], str) and wq[0] in CONTROL_WORDS:
                    wq.pop(0)
            else:
                val = _widget_default(sp)
                if val is None:
                    continue
            inputs[name] = val

        api[str(n["id"])] = {"class_type": t, "inputs": inputs}
    return api


def find_node(api: dict, *class_substrings):
    for nid, node in api.items():
        if any(s.lower() in node["class_type"].lower() for s in class_substrings):
            return nid
    return None
