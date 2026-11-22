"""Builds the store hero banner from the round screenshots."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

store = sys.argv[1]
W, H = int(sys.argv[2]), int(sys.argv[3])
out_path = sys.argv[4]

PALE = (0xCC, 0xEE, 0xFF)
SKY = (0x00, 0xAA, 0xFF)
BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
REG = r"C:\Windows\Fonts\segoeui.ttf"

img = Image.new("RGB", (W, H), (6, 8, 12))

# Soft glows behind the faces
glow = Image.new("RGB", (W, H), (0, 0, 0))
g = ImageDraw.Draw(glow)
g.ellipse([W * 0.50, H * 0.05, W * 1.05, H * 0.95], fill=(0, 60, 110))
g.ellipse([W * -0.15, H * 0.35, W * 0.35, H * 1.2], fill=(0, 25, 50))
glow = glow.filter(ImageFilter.GaussianBlur(H * 0.18))
img = Image.blend(img, glow, 0.85)


def face(name, size):
    f = Image.open(f"{store}/{name}").convert("RGBA")
    return f.resize((size, size), Image.LANCZOS)


def shadow(size):
    sh = Image.new("RGBA", (size + 80, size + 80), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([40, 50, size + 40, size + 50], fill=(0, 0, 0, 200))
    return sh.filter(ImageFilter.GaussianBlur(22))


# Faces: green and red behind, blue in front
big = int(H * 0.74)
small = int(H * 0.52)
cx = int(W * 0.725)
cy = H // 2
for name, dx in [("screenshot-1.png", -0.14), ("screenshot-2.png", 0.14)]:
    x = int(cx + W * dx - small / 2)
    y = cy - small // 2
    img.paste(shadow(small), (x - 40, y - 40), shadow(small))
    img.paste(face(name, small), (x, y), face(name, small))
x = cx - big // 2
y = cy - big // 2
img.paste(shadow(big), (x - 40, y - 40), shadow(big))
img.paste(face("screenshot-0.png", big), (x, y), face("screenshot-0.png", big))

# Title in the face's gradient
d = ImageDraw.Draw(img)
title = "Replica"
tf = ImageFont.truetype(BOLD, int(H * 0.17))
tx, ty = int(W * 0.06), int(H * 0.27)
l, t, r, b = d.textbbox((tx, ty), title, font=tf)
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).text((tx, ty), title, font=tf, fill=255)
grad = Image.new("RGB", (W, H))
gp = ImageDraw.Draw(grad)
for yy in range(H):
    k = min(1, max(0, (yy - t) / max(1, b - t)))
    gp.line([(0, yy), (W, yy)], fill=tuple(round(PALE[i] + (SKY[i] - PALE[i]) * k) for i in range(3)))
img.paste(grad, (0, 0), mask)

sf = ImageFont.truetype(REG, int(H * 0.058))
d.text((tx + 4, b + H * 0.04), "WATCH FACE", font=sf, fill=PALE)
lf = ImageFont.truetype(REG, int(H * 0.038))
lines = ["Gradient time, health stats and weather", "Live heart rate and stress graphs", "Your colours, your way"]
ly = b + H * 0.16
for line in lines:
    d.text((tx + 4, ly), line, font=lf, fill=(170, 190, 205))
    ly += H * 0.068

img.save(out_path)
print("wrote", out_path, img.size)
