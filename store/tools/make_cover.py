"""Builds the square store cover image from the round screenshots."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

store = sys.argv[1]
S = int(sys.argv[2])
out_path = sys.argv[3]

PALE = (0xCC, 0xEE, 0xFF)
SKY = (0x00, 0xAA, 0xFF)
BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
REG = r"C:\Windows\Fonts\segoeui.ttf"

# Drawn at 2x, then shrunk for smooth edges
W = H = S * 2
img = Image.new("RGB", (W, H), (6, 8, 12))

glow = Image.new("RGB", (W, H), (0, 0, 0))
ImageDraw.Draw(glow).ellipse([W * 0.05, H * 0.0, W * 0.95, H * 0.8], fill=(0, 60, 110))
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.15))
img = Image.blend(img, glow, 0.85)


def face(name, size):
    return Image.open(f"{store}/{name}").convert("RGBA").resize((size, size), Image.LANCZOS)


def shadow(size):
    sh = Image.new("RGBA", (size + 80, size + 80), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([40, 50, size + 40, size + 50], fill=(0, 0, 0, 200))
    return sh.filter(ImageFilter.GaussianBlur(22))


# Green and red behind, blue in front
big = int(W * 0.62)
small = int(W * 0.44)
cx = W // 2
cy = int(H * 0.39)
for name, dx in [("screenshot-1.png", -0.27), ("screenshot-2.png", 0.27)]:
    x = int(cx + W * dx - small / 2)
    y = cy - small // 2
    img.paste(shadow(small), (x - 40, y - 40), shadow(small))
    img.paste(face(name, small), (x, y), face(name, small))
x, y = cx - big // 2, cy - big // 2
img.paste(shadow(big), (x - 40, y - 40), shadow(big))
img.paste(face("screenshot-0.png", big), (x, y), face("screenshot-0.png", big))

# Title in the face's gradient, centered under the faces
d = ImageDraw.Draw(img)
tf = ImageFont.truetype(BOLD, int(H * 0.13))
l, t, r, b = d.textbbox((0, 0), "Replica", font=tf)
tx = (W - (r - l)) / 2 - l
ty = H * 0.745 - t
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).text((tx, ty), "Replica", font=tf, fill=255)
top, bottom = H * 0.745, H * 0.745 + (b - t)
grad = Image.new("RGB", (W, H))
gp = ImageDraw.Draw(grad)
for yy in range(H):
    k = min(1, max(0, (yy - top) / (bottom - top)))
    gp.line([(0, yy), (W, yy)], fill=tuple(round(PALE[i] + (SKY[i] - PALE[i]) * k) for i in range(3)))
img.paste(grad, (0, 0), mask)

sf = ImageFont.truetype(REG, int(H * 0.045))
l, t, r, b2 = d.textbbox((0, 0), "WATCH FACE", font=sf)
d.text(((W - (r - l)) / 2 - l, bottom + H * 0.03), "WATCH FACE", font=sf, fill=PALE)

img = img.resize((S, S), Image.LANCZOS)
img.save(out_path, optimize=True)
print("wrote", out_path, img.size)
