#!/usr/bin/env python3
r"""
generate_shibkart_audio.py — synthesize all ShibKart SFX as WAV files.

These are short procedural sound effects (pure DSP, no AI / no models needed), so
the game has sound the moment you run this. Drop-in convention:

    MUSIC  (you provide):  assets/audio/music/<track_id>.mp3   (one loop per map)
    SFX    (this script):  assets/audio/sfx/<name>.wav

Run:
    python tools/generate_shibkart_audio.py            # write all SFX
    python tools/generate_shibkart_audio.py --list     # just list what it makes

Requires: numpy (stdlib `wave` for output). Replace any .wav with your own if you
prefer hand-made / AI-generated sounds — the game loads whatever is there, and is
silent (no crash) for anything missing.
"""
from __future__ import annotations
import argparse, math, wave, struct, sys
from pathlib import Path

try:
    import numpy as np
except ImportError:
    print("!! pip install numpy"); raise

HERE = Path(__file__).resolve().parent
SFX_DIR = HERE.parent / "assets" / "audio" / "sfx"
MUSIC_DIR = HERE.parent / "assets" / "audio" / "music"
SR = 44100


# ---- dsp helpers ----------------------------------------------------------------
def _t(dur): return np.linspace(0, dur, int(SR * dur), endpoint=False)

def sine(f, dur, amp=0.7): return amp * np.sin(2 * np.pi * f * _t(dur))
def saw(f, dur, amp=0.5):
    ph = (f * _t(dur)) % 1.0
    return amp * (2 * ph - 1)
def square(f, dur, amp=0.5): return amp * np.sign(np.sin(2 * np.pi * f * _t(dur)))
def noise(dur, amp=0.6, seed=0):
    rng = np.random.default_rng(seed)
    return amp * rng.uniform(-1, 1, int(SR * dur))
def sweep(f0, f1, dur, amp=0.6, kind="sine"):
    t = _t(dur)
    f = np.linspace(f0, f1, t.size)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return amp * (np.sin(ph) if kind == "sine" else (2 * ((ph / (2 * np.pi)) % 1.0) - 1))
def adsr(x, a=0.01, d=0.05, s=0.7, r=0.1):
    n = x.size
    env = np.ones(n)
    ai = int(a * SR); di = int(d * SR); ri = int(r * SR)
    if ai: env[:ai] = np.linspace(0, 1, ai)
    if di: env[ai:ai + di] = np.linspace(1, s, di)
    env[ai + di:n - ri] = s
    if ri: env[n - ri:] = np.linspace(s, 0, ri)
    return x * env

def tri(f, dur, amp=0.5):
    ph = (f * _t(dur)) % 1.0
    return amp * (2 * np.abs(2 * ph - 1) - 1)      # triangle: soft, few harmonics

def lowpass(x, cutoff=0.15):
    # gentle 1-pole low-pass to take the harsh edge off noise / saw
    y = np.empty_like(x); prev = 0.0
    for i in range(x.size):
        prev += cutoff * (x[i] - prev); y[i] = prev
    return y

def _edges(x, ms=6):
    # short fade in/out so nothing clicks
    n = int(SR * ms / 1000)
    if x.size > 2 * n and n > 0:
        x[:n] *= np.linspace(0, 1, n); x[-n:] *= np.linspace(1, 0, n)
    return x

def _norm(x, peak=0.55):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak

def write(name, samples, peak=0.55):
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    x = _edges(_norm(np.asarray(samples, dtype=np.float64), peak))
    pcm = np.clip(x * 32767, -32768, 32767).astype("<i2")
    with wave.open(str(SFX_DIR / f"{name}.wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  [ok] assets/audio/sfx/{name}.wav  ({len(pcm)/SR:.2f}s)")


# ---- the sound set --------------------------------------------------------------
def build_all():
    # cute UI/gameplay blips — soft sine/triangle tones, gentle envelopes, low level
    write("beep", adsr(sine(784, 0.09), 0.005, 0.02, 0.6, 0.05), 0.4)
    write("go",   adsr(sine(1046, 0.30) + 0.25 * sine(1568, 0.30), 0.006, 0.03, 0.7, 0.14), 0.5)
    write("lap",  adsr(np.concatenate([tri(880, 0.07), tri(1319, 0.12)]), 0.005, 0.02, 0.7, 0.06), 0.45)
    fin = np.concatenate([adsr(tri(f, 0.13), 0.006, 0.03, 0.7, 0.05) for f in (523, 659, 784, 1047)])
    write("finish", fin, 0.5)
    write("coin", np.concatenate([adsr(sine(1319, 0.05), 0.002, 0.01, 0.8, 0.02),
                                  adsr(sine(1760, 0.11), 0.002, 0.02, 0.7, 0.05)]), 0.4)
    # whooshes: LOW-PASSED noise (soft air, not white static) + a warm tone
    write("boost", adsr(lowpass(sweep(260, 900, 0.4), 0.25) + 0.35 * lowpass(noise(0.4, 0.5, 1), 0.12), 0.02, 0.06, 0.6, 0.2), 0.5)
    write("turbo", adsr(lowpass(sweep(380, 1300, 0.3), 0.35) + 0.3 * sine(1760, 0.3), 0.006, 0.04, 0.7, 0.14), 0.5)
    write("drift", adsr(0.35 * lowpass(noise(0.5, 0.5, 2), 0.08) + 0.25 * tri(1400, 0.5), 0.03, 0.06, 0.6, 0.25), 0.32)
    write("bump", adsr(lowpass(sine(150, 0.13) + 0.4 * noise(0.13, 0.4, 3), 0.2), 0.002, 0.02, 0.5, 0.09), 0.5)
    write("item_pickup", adsr(sweep(660, 1046, 0.15), 0.006, 0.02, 0.7, 0.06), 0.45)
    write("shell", adsr(lowpass(sweep(1200, 480, 0.24), 0.4) + 0.2 * tri(700, 0.24), 0.006, 0.03, 0.6, 0.1), 0.45)
    write("banana", adsr(tri(300, 0.18) + sweep(300, 170, 0.18), 0.01, 0.03, 0.6, 0.08), 0.42)
    write("oil", adsr(0.4 * lowpass(noise(0.22, 0.5, 5), 0.06) + 0.25 * sine(200, 0.22), 0.006, 0.03, 0.5, 0.1), 0.4)
    sh = np.concatenate([adsr(sine(f, 0.1), 0.01, 0.02, 0.7, 0.04) for f in (523, 784, 1047)])
    write("shield", sh, 0.42)
    write("lightning", adsr(0.4 * lowpass(noise(0.3, 0.6, 6), 0.3) + 0.35 * sweep(1500, 500, 0.3), 0.004, 0.03, 0.5, 0.15), 0.5)
    gh = sine(392, 0.42) * (1 + 0.25 * np.sin(2 * np.pi * 6 * _t(0.42)))  # gentle vibrato
    write("ghost", adsr(gh, 0.03, 0.05, 0.6, 0.18), 0.4)
    write("click", adsr(tri(880, 0.04), 0.001, 0.01, 0.7, 0.02), 0.35)
    write("select", adsr(sine(660, 0.09) + 0.3 * sine(990, 0.09), 0.004, 0.02, 0.7, 0.04), 0.4)
    # seamless loops (integer cycle counts): WARM engine hum, soft grass rumble
    eng = lowpass(0.6 * tri(80, 1.0) + 0.35 * sine(160, 1.0) + 0.15 * tri(240, 1.0), 0.3)
    write("engine", eng, 0.42)
    write("offroad", lowpass(noise(1.0, 0.7, 7), 0.05), 0.35)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    names = ["beep", "go", "lap", "finish", "coin", "boost", "turbo", "drift", "bump",
             "item_pickup", "shell", "banana", "oil", "shield", "lightning", "ghost",
             "click", "select", "engine", "offroad"]
    if args.list:
        print("SFX this script generates ->", ", ".join(names))
        print("MUSIC you provide (mp3) ->", MUSIC_DIR)
        return 0
    print("Generating ShibKart SFX ->", SFX_DIR)
    build_all()
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    print("\nDONE. Drop your per-map music mp3s into:", MUSIC_DIR)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
