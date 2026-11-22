"""Draws the Replica launcher icon: gradient ring, gradient "R", and a small bar graph."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageChops

PALE = (0xCC, 0xEE, 0xFF)
SKY = (0x00, 0xAA, 0xFF)
FONT = r"C:\Windows\Fonts\segoeuib.ttf"


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, top, bottom, y0=0, y1=None):
    """Full-size image whose colour runs top->bottom between rows y0 and y1."""
    y1 = size if y1 is None else y1
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = min(1, max(0, (y - y0) / max(1, y1 - y0)))
        c = lerp(top, bottom, t)
        for x in range(size):
            px[x, y] = c
    return img


def icon(size):
    s = size * 8  # supersample, then shrink for smooth edges
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Black disc
    disc = Image.new("L", (s, s), 0)
    ImageDraw.Draw(disc).ellipse([0, 0, s - 1, s - 1], fill=255)
    out.paste((0, 0, 0, 255), (0, 0), disc)

    # Gradient ring
    ring = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(ring)
    w = round(s * 0.05)
    d.ellipse([w * 0.4, w * 0.4, s - 1 - w * 0.4, s - 1 - w * 0.4], outline=255, width=w)
    out.paste(vertical_gradient(s, PALE, SKY), (0, 0), ring)

    # Gradient "R", slightly above center
    mask = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(mask)
    font = ImageFont.truetype(FONT, round(s * 0.5))
    l, t, r, b = d.textbbox((0, 0), "R", font=font)
    tx = (s - (r - l)) / 2 - l
    ty = s * 0.19 - t
    d.text((tx, ty), "R", font=font, fill=255)
    top, bottom = s * 0.19, s * 0.19 + (b - t)
    out.paste(vertical_gradient(s, PALE, SKY, round(top), round(bottom)), (0, 0), mask)

    # Small bar graph under the letter
    bars = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(bars)
    heights = [0.35, 0.6, 0.9, 1.0, 0.75, 0.5, 0.3]
    bw = s * 0.05
    gap = s * 0.025
    total = len(heights) * bw + (len(heights) - 1) * gap
    x = (s - total) / 2
    base = s * 0.8
    maxh = s * 0.11
    for hgt in heights:
        d.rectangle([x, base - maxh * hgt, x + bw, base], fill=255)
        x += bw + gap
    out.paste(vertical_gradient(s, PALE, SKY, round(base - maxh), round(base)), (0, 0), bars)

    # Keep everything inside the disc
    alpha = ImageChops.multiply(out.split()[3], disc)
    out.putalpha(alpha)
    return out.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    for size, path in zip(map(int, sys.argv[1::2]), sys.argv[2::2]):
        icon(size).save(path)
        print("wrote", path)
