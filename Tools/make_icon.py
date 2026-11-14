#!/usr/bin/env python3
"""Generates NEEDLE's original 1024x1024 app icon (no alpha channel). Run from the repo root."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

bg = np.zeros((S, S, 3), np.float32)
t = yy / S
bg[:] = (np.array([22, 22, 24]) * (1 - t[..., None]) + np.array([7, 7, 8]) * t[..., None])
d = np.sqrt((xx - 0.30 * S) ** 2 + (yy - 0.22 * S) ** 2) / S
bg += (np.clip(0.55 - d, 0, 1) ** 2 * 60)[..., None]

cx, cy, R = 0.50 * S, 0.54 * S, 0.40 * S
dx, dy = xx - cx, yy - cy
r = np.sqrt(dx * dx + dy * dy)
ang = (np.arctan2(dy, dx) / (2 * np.pi)) % 1.0
disc = np.clip((R - r) / 2.0, 0, 1)

base = np.array([138, 24, 38], np.float32)
shade = 0.55 + 0.55 * np.clip(1 - r / R, 0, 1) ** 0.8
col = base[None, None, :] * shade[..., None]
g = 0.5 + 0.5 * np.sin(r / 3.1)
col *= (0.86 + 0.14 * g)[..., None]
rim = np.clip((r - 0.955 * R) / (0.045 * R), 0, 1)
col += (rim * 38)[..., None]

def lobe(c, w, a):
    dd = np.minimum(np.abs(ang - c), 1 - np.abs(ang - c))
    return a * np.exp(-(dd / w) ** 2)
sheen = lobe(0.10, 0.035, 1.0) + lobe(0.15, 0.012, 0.5) + lobe(0.62, 0.05, 0.85) + lobe(0.36, 0.018, 0.35)
ring = np.clip((r - 0.34 * R) / (0.05 * R), 0, 1) * np.clip((0.97 * R - r) / (0.03 * R), 0, 1)
col += (sheen * ring * 105)[..., None]

img = bg * (1 - disc[..., None]) + col * disc[..., None]

label = np.clip((0.30 * R - r) / 2.0, 0, 1)
lab = np.array([232, 214, 178], np.float32)[None, None, :] * (0.92 + 0.08 * np.clip(1 - r / (0.3 * R), 0, 1))[..., None]
img = img * (1 - label[..., None]) + lab * label[..., None]
ringl = np.clip(1 - np.abs(r - 0.255 * R) / 2.5, 0, 1) * (label > 0)
img -= (ringl * 70)[..., None]
hole = np.clip((0.035 * R - r) / 2.0, 0, 1)
img = img * (1 - hole[..., None]) + np.array([8, 8, 9], np.float32) * hole[..., None]

im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
arm = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ad = ImageDraw.Draw(arm)
px, py = 0.84 * S, 0.17 * S
tx, ty = 0.66 * S, 0.50 * S
ad.line([(px, py), (tx, ty)], fill=(205, 207, 212, 255), width=int(0.018 * S))
ad.ellipse([px - 0.055 * S, py - 0.055 * S, px + 0.055 * S, py + 0.055 * S], fill=(48, 49, 53, 255), outline=(170, 172, 178, 255), width=6)
ad.ellipse([px - 0.022 * S, py - 0.022 * S, px + 0.022 * S, py + 0.022 * S], fill=(120, 122, 128, 255))
ad.polygon([(tx - 0.03 * S, ty - 0.012 * S), (tx + 0.02 * S, ty - 0.035 * S), (tx + 0.04 * S, ty + 0.012 * S), (tx - 0.01 * S, ty + 0.035 * S)], fill=(30, 30, 33, 255))
shadow = arm.filter(ImageFilter.GaussianBlur(0.012 * S))
sh = np.array(shadow).astype(np.float32)
sh[..., :3] = 0
sh[..., 3] *= 0.55
shadow = Image.fromarray(sh.astype(np.uint8), "RGBA")
im = im.convert("RGBA")
im.alpha_composite(shadow, (int(0.012 * S), int(0.02 * S)))
im.alpha_composite(arm)

out = im.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save("Needle/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
print("icon written")
