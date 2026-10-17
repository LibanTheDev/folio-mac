#!/usr/bin/env python3
"""Composes the README hero image from real Folio screenshots (no mock-ups)."""
import os
from PIL import Image, ImageDraw, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
shots = os.path.join(here, "..", "docs", "assets", "screenshots")
W, H = 2400, 1350

def gradient(w, h):
    top, bottom = (24, 28, 38), (12, 14, 20)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    # Soft icy-blue glow, echoing the app's accent.
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse([w * 0.45, -h * 0.4, w * 1.25, h * 0.7], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    blue = Image.new("RGB", (w, h), (57, 135, 229))
    return Image.composite(blue, img, glow.point(lambda v: int(v * 0.55)))

def window(path, width, radius=26):
    im = Image.open(path).convert("RGB")
    im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0), mask)
    return out

def shadow(size, radius=26, blur=40, opacity=150):
    pad = blur * 2
    s = Image.new("RGBA", (size[0] + pad * 2, size[1] + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle([pad, pad + 18, pad + size[0], pad + size[1] + 18], radius=radius, fill=(0, 0, 0, opacity))
    return s.filter(ImageFilter.GaussianBlur(blur)), pad

canvas = gradient(W, H).convert("RGBA")
back = window(os.path.join(shots, "library-gallery.jpg"), 1500)
front = window(os.path.join(shots, "home-dashboard.jpg"), 1720)
for img, (x, y) in [(back, (W - 1500 - 90, 70)), (front, (110, 230))]:
    sh, pad = shadow(img.size)
    canvas.alpha_composite(sh, (x - pad, y - pad))
    canvas.alpha_composite(img, (x, y))
canvas = canvas.crop((0, 0, W, H)).convert("RGB")
canvas.save(os.path.join(shots, "hero.jpg"), quality=86, optimize=True, progressive=True)
print("hero.jpg", canvas.size)
