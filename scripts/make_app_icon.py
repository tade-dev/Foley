#!/usr/bin/env python3
"""Renders the Foley app icon: a glowing amber-to-blue orb on the app's dark background."""
import json, os, math
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "Foley", "Assets.xcassets", "AppIcon.appiconset")
S = 1024
img = Image.new("RGB", (S, S), (10, 10, 12))

# Soft blue glow in the top half, like the board's mesh.
glow = Image.new("RGB", (S, S), (10, 10, 12))
gd = ImageDraw.Draw(glow)
gd.ellipse((S * 0.05, -S * 0.2, S * 0.95, S * 0.75), fill=(21, 33, 61))
glow = glow.filter(ImageFilter.GaussianBlur(140))
img = Image.blend(img, glow, 1.0)

# Orb glow halo.
halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(halo)
hd.ellipse((S * 0.22, S * 0.22, S * 0.78, S * 0.78), fill=(255, 181, 71, 150))
halo = halo.filter(ImageFilter.GaussianBlur(70))
img.paste(halo, (0, 0), halo)

# Orb: radial gradient highlight → amber base → shadow, centre offset to (36%, 34%).
r = int(S * 0.26)
cx, cy = S // 2, S // 2
orb = Image.new("RGBA", (2 * r, 2 * r), (0, 0, 0, 0))
px = orb.load()
hi, base, sh = (255, 217, 160), (255, 181, 71), (138, 78, 16)
fx, fy = 2 * r * 0.36, 2 * r * 0.34
for y in range(2 * r):
    for x in range(2 * r):
        dx, dy = x - r, y - r
        if dx * dx + dy * dy > r * r:
            continue
        d = math.hypot(x - fx, y - fy) / (2 * r * 0.62)
        if d < 0.38:
            t = d / 0.38; c = tuple(int(hi[i] + (base[i] - hi[i]) * t) for i in range(3))
        elif d < 0.78:
            t = (d - 0.38) / 0.4; c = tuple(int(base[i] + (sh[i] - base[i]) * t) for i in range(3))
        else:
            c = sh
        edge = r - math.hypot(dx, dy)
        a = 255 if edge > 2 else int(max(0, edge / 2) * 255)
        px[x, y] = (*c, a)
img.paste(orb, (cx - r, cy - r), orb)

# Thin dashed orbit ring, like the Home screen.
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
R = int(S * 0.40)
for i in range(60):
    a0 = i * 6; a1 = a0 + 3.2
    rd.arc((cx - R, cy - R, cx + R, cy + R), a0, a1, fill=(169, 180, 204, 110), width=5)
img.paste(ring, (0, 0), ring)

os.makedirs(OUT, exist_ok=True)
img.save(os.path.join(OUT, "icon-1024.png"))
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(OUT, "Contents.json"), "w"), indent=2)
print("wrote", os.path.relpath(os.path.join(OUT, "icon-1024.png"), ROOT))
