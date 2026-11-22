"""Crops the 454x454 round watch screen out of a simulator window screenshot."""
import sys
from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
W, H = im.size

def lit(p):
    # Blue ring pixels only (excludes the white window and the grey bezel)
    return p[2] > 150 and p[2] - p[0] > 40

# The border ring is the outermost bright pixel on the screen; find its extents
# along the middle row and column of the watch display area.
row = 485
xs = [x for x in range(W) if lit(im.getpixel((x, row)))]
cx = (xs[0] + xs[-1]) // 2
ys = [y for y in range(60, H - 60) if lit(im.getpixel((cx, y)))]
cy = (ys[0] + ys[-1]) // 2

size = 454
box = (cx - size // 2, cy - size // 2, cx - size // 2 + size, cy - size // 2 + size)
face = im.crop(box)

# Round mask, transparent outside the screen
mask = Image.new("L", (size * 4, size * 4), 0)
ImageDraw.Draw(mask).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
mask = mask.resize((size, size), Image.LANCZOS)
out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
out.paste(face, (0, 0), mask)
out.save(dst)
print("center", cx, cy, "->", dst)
