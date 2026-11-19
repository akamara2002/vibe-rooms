#!/usr/bin/env python3
"""Draws the Vibe Rooms launcher icon (original artwork, no fonts, no assets).

Writes to assets/icon/:
  icon.png             1024 px master: gradient rounded square + headphones
  icon_foreground.png  1024 px transparent, glyph inside the adaptive safe zone
  icon_background.png  1024 px gradient square (adaptive icon background)
  splash.png           768 px transparent glyph for the native splash
  mark.png             256 px copy of the master, shown on the login screen

Run:  python3 tool/generate_icons.py      (needs Pillow: pip install pillow,
      ideally in a virtual environment outside the repo)
Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
SIZE = 1024
SS = 4  # supersampling for smooth edges

# Same colours as lib/core/widgets/gradient_background.dart.
TOP = (0x2B, 0x1B, 0x5A)
MID = (0x13, 0x0B, 0x2B)
BOTTOM = (0x0A, 0x07, 0x12)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    """Diagonal gradient from the deep purple to near-black."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    span = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / span
            px[x, y] = lerp(TOP, MID, t / 0.55) if t < 0.55 else lerp(
                MID, BOTTOM, (t - 0.55) / 0.45
            )
    return img


def glyph(size, scale):
    """White headphones on a transparent square canvas of [size] px.

    [scale] is the width of the glyph as a fraction of the canvas."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = big * scale  # glyph width
    cx, cy = big / 2, big / 2 + s * 0.04
    white = (255, 255, 255, 255)

    r = s * 0.5 - s * 0.085  # band centre-line radius
    t = s * 0.085            # band thickness
    top = cy - r - s * 0.10
    # Band: a half ring. Its ends are hidden inside the ear cups.
    box = [cx - r, top, cx + r, top + 2 * r]
    d.arc(box, 180, 360, fill=white, width=round(t))

    # Ear cups: rounded rectangles with a lavender pad on the inner face.
    cup_w, cup_h = s * 0.22, s * 0.42
    cup_top = top + r - t * 0.6
    for sign in (-1, 1):
        x_mid = cx + sign * r
        x0, x1 = x_mid - cup_w / 2, x_mid + cup_w / 2
        d.rounded_rectangle([x0, cup_top, x1, cup_top + cup_h],
                            radius=cup_w * 0.3, fill=white)
        pad_w = cup_w * 0.36
        inset = cup_w * 0.12
        px0 = x1 - inset - pad_w if sign == -1 else x0 + inset
        d.rounded_rectangle(
            [px0, cup_top + cup_h * 0.2, px0 + pad_w, cup_top + cup_h * 0.8],
            radius=pad_w * 0.5, fill=(206, 190, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def rounded_mask(size, radius_ratio=0.225):
    big = size * SS
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=big * radius_ratio, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    bg = gradient(SIZE)
    bg.save(OUT / "icon_background.png")

    master = bg.convert("RGBA")
    master.alpha_composite(glyph(SIZE, 0.62))
    master.putalpha(rounded_mask(SIZE))
    master.save(OUT / "icon.png")

    # Adaptive foreground: flutter_launcher_icons insets it by 16% per side, and
    # the visible circle is 66% of the 108 dp canvas, so the
    # whole glyph (including the soft pads) stays well inside it.
    glyph(SIZE, 0.86).save(OUT / "icon_foreground.png")

    glyph(768, 0.80).save(OUT / "splash.png")
    master.resize((256, 256), Image.LANCZOS).save(OUT / "mark.png")
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
