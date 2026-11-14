#!/usr/bin/env python3
"""Synthesise placeholder demo sounds (Phase A). Phase B replaces them with ElevenLabs audio.

Reads Foley/Resources/Demo/demo-scenes.json and writes one AAC .m4a per sound.
Loops are made seamless with an end-to-start crossfade. Requires numpy and ffmpeg.
"""
import json, os, subprocess, tempfile, wave, struct, sys
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
DEMO = os.path.join(ROOT, "Foley", "Resources", "Demo")
SR = 44100
rng = np.random.default_rng(7)

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc); y[i] = acc
    return y

def noise(n): return rng.standard_normal(n)

def env(n, attack, release):
    e = np.ones(n)
    a = int(attack * SR); r = int(release * SR)
    e[:a] = np.linspace(0, 1, a); e[n - r:] = np.linspace(1, 0, r)
    return e

def seamless(x, fade=0.25):
    f = int(fade * SR)
    head, tail = x[:f].copy(), x[-f:].copy()
    ramp = np.linspace(0, 1, f)
    x = x[:-f].copy()
    x[:f] = head * ramp + tail * (1 - ramp)
    return x

def synth(name, dur, loop):
    n = int((dur + (0.25 if loop else 0)) * SR); t = np.arange(n) / SR
    if name == "creaking-hull":
        base = lowpass(noise(n), 0.02) * 0.6
        creak = np.sin(2 * np.pi * (60 + 25 * np.sin(2 * np.pi * 0.3 * t)) * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.17 * t))
        x = base + 0.4 * creak * lowpass(np.abs(noise(n)), 0.001)
    elif name == "thunder-crack":
        x = lowpass(noise(n), 0.08) * np.exp(-t * 1.2) * 1.5 + lowpass(noise(n), 0.01) * np.exp(-t * 0.5)
    elif name in ("heavy-rain", "rain-on-window"):
        x = (noise(n) - lowpass(noise(n), 0.3)) * (0.8 if name == "heavy-rain" else 0.5)
        x += lowpass(noise(n), 0.05) * 0.3
    elif name == "howling-wind":
        x = lowpass(noise(n), 0.03) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t))
        x += 0.2 * np.sin(2 * np.pi * (300 + 150 * np.sin(2 * np.pi * 0.07 * t)) * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * t))
    elif name == "waves-on-hull":
        x = lowpass(noise(n), 0.015) * (0.3 + 0.7 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.12 * t)) ** 2)
    elif name == "grumpy-cat":
        x = np.sin(2 * np.pi * (420 - 120 * t) * t) * np.exp(-t * 2.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t))
    elif name == "espresso-machine":
        x = (noise(n) - lowpass(noise(n), 0.5)) * env(n, 0.05, 0.6) * 0.8
    elif name == "quiet-chatter":
        x = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * lowpass(np.abs(noise(n)), 0.0005) for f in (180, 230, 310, 420)) * 0.25
        x = lowpass(x, 0.2)
    elif name == "ceramic-cups":
        x = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * 9) for f in (2100, 3300, 4700)) * 0.4
    else:
        x = noise(n) * 0.2
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.7
    x = seamless(x) if loop else x * env(n, 0.005, 0.05)
    return x.astype(np.float32)

def write(path, x):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-ac", "2", "-c:a", "aac", "-b:a", "128k", path], check=True)
    os.unlink(tmp.name)

def main():
    data = json.load(open(os.path.join(DEMO, "demo-scenes.json")))
    for scene in data["scenes"]:
        for s in scene["sounds"]:
            out = os.path.join(DEMO, s["file"] + ".m4a")
            write(out, synth(s["file"], s["duration"], s["kind"] == "loop"))
            print("wrote", os.path.relpath(out, ROOT))

if __name__ == "__main__":
    main()
