"""Turns the draw calls tools/preview.lua recorded into pictures: internal/preview/<name>.png.

Usage: python -P tools/render_preview.py [<name> ...]

An approximation of the game: Bahnschrift stands in for the game's fonts, the scanline strip is drawn
as lines, and a starfield stands in for the space behind the galaxy map. Shapes, layers, colours and
text positions are the ones the mod asks for.
"""
import json
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent.parent
OUT = HERE / "internal" / "preview"
W, H = 1920, 1080
FONTS = {}


def font(size, large):
    key = (round(size), large)
    if key not in FONTS:
        for name in (["bahnschrift.ttf", "arialbd.ttf"] if large else ["bahnschrift.ttf", "arial.ttf"]):
            try:
                FONTS[key] = ImageFont.truetype(name, max(6, round(size * 0.92)))
                break
            except OSError:
                continue
    return FONTS[key]


def rgba(c):
    return tuple(max(0, min(255, round(v))) for v in c[:3]) + (max(0, min(255, round(c[3]))),)


def backdrop():
    img = Image.new("RGB", (W, H), (6, 9, 16))
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(7)
    for _ in range(900):
        x, y = rnd.random() * W, rnd.random() * H
        b = rnd.randint(60, 200)
        r = rnd.choice([0.6, 0.8, 1.2])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(b, b, b + 20, 255))
    # A faint nebula, as the galaxy map's space cloud.
    for _ in range(40):
        x, y, r = rnd.random() * W, rnd.random() * H, rnd.randint(80, 260)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(40, 60, 110, 6))
    return img


def render(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    ops = sorted(enumerate(data["ops"]), key=lambda e: (e[1]["z"] + (1 if e[1]["op"] == "text" else 0), e[0]))
    img = backdrop()
    d = ImageDraw.Draw(img, "RGBA")

    def Y(y):
        return H - y

    for _, op in ops:
        kind = op["op"]
        c = rgba(op.get("c", [255, 255, 255, 255]))
        if c[3] <= 0:
            continue
        if kind == "rect":
            x0, y0, x1, y1 = op["x"], Y(op["y"] + op["h"]), op["x"] + op["w"], Y(op["y"])
            if op.get("clip"):
                cx, cy, cw, ch = op["clip"]
                x0, x1 = max(x0, cx), min(x1, cx + cw)
                y0, y1 = max(y0, Y(cy + ch)), min(y1, Y(cy))
            if x1 > x0 and y1 > y0:
                d.rectangle([x0, y0, x1, y1], fill=c)
        elif kind == "poly":
            pts = op["pts"]
            d.polygon([(pts[i], Y(pts[i + 1])) for i in range(0, len(pts), 2)], fill=c)
        elif kind == "outline":
            pts = op["pts"]
            xy = [(pts[i], Y(pts[i + 1])) for i in range(0, len(pts), 2)]
            d.line(xy + [xy[0]], fill=c, width=max(1, round(op.get("width", 1))))
        elif kind == "text":
            size = op["size"]
            f = font(size, op.get("font") == "body_large")
            anchor = {"left": "ls", "center": "ms", "right": "rs"}[op.get("align", "left")]
            s = op["s"]
            if op.get("tracking"):
                s = s  # Pillow has no letter spacing; the width is close enough for a preview.
            d.text((op["x"], Y(op["y"])), s, font=f, fill=c, anchor=anchor)
        elif kind == "icon" and op["name"] == "galcamp_scanlines":
            for y in range(int(op["y"]), int(op["y"] + op["h"]), 4):
                if 0 <= y < H:
                    d.line([(0, Y(y)), (W, Y(y))], fill=(255, 255, 255, max(1, c[3] // 10)))
        elif kind == "glyph" and op["name"] == "shield":
            x, y, s = op["x"], op["y"], op["size"] / 16
            pts = [8, 15.5, 2, 13, 2, 7, 8, 0.5, 14, 7, 14, 13]
            d.polygon([(x + pts[i] * s, Y(y + pts[i + 1] * s)) for i in range(0, len(pts), 2)], fill=c)
    dest = path.with_suffix(".png")
    img.save(dest)
    print(dest)


def main():
    names = sys.argv[1:]
    files = [OUT / f"{n}.json" for n in names] if names else sorted(OUT.glob("*.json"))
    for f in files:
        render(f)


if __name__ == "__main__":
    main()
