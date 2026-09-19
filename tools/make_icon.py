"""SalesGO launcher ikon generatori (build vaqtida ishlaydi).
Yashil-havorang gradient rounded kvadrat + oq 'S'. Adaptive foreground ham.
"""
import os
from PIL import Image, ImageDraw, ImageFont

SZ = 1024
OUT = "assets/icon"
os.makedirs(OUT, exist_ok=True)

C1 = (16, 185, 129)   # emerald #10B981
C2 = (6, 182, 212)    # cyan    #06B6D4


def font(px):
    for p in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def draw_s(img, color, scale=0.62):
    d = ImageDraw.Draw(img)
    f = font(int(SZ * scale))
    t = "S"
    try:
        box = d.textbbox((0, 0), t, font=f)
        w, h = box[2] - box[0], box[3] - box[1]
        d.text(((SZ - w) / 2 - box[0], (SZ - h) / 2 - box[1]), t, font=f, fill=color)
    except Exception:
        d.text((SZ * 0.3, SZ * 0.2), t, font=f, fill=color)


def gradient():
    g = Image.new("RGB", (SZ, SZ), C1)
    dr = ImageDraw.Draw(g)
    for y in range(SZ):
        t = y / SZ
        col = tuple(int(C1[i] + (C2[i] - C1[i]) * t) for i in range(3))
        dr.line([(0, y), (SZ, y)], fill=col)
    return g


# ---- icon.png (to'liq: gradient rounded kvadrat + oq S) ----
icon = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
mask = Image.new("L", (SZ, SZ), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SZ, SZ], radius=int(SZ * 0.22), fill=255)
icon.paste(gradient(), (0, 0), mask)
draw_s(icon, (255, 255, 255, 255))
icon.save(os.path.join(OUT, "icon.png"))

# ---- foreground.png (shaffof fon + oq S, adaptive xavfsiz zona) ----
fg = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
draw_s(fg, (255, 255, 255, 255), scale=0.42)
fg.save(os.path.join(OUT, "foreground.png"))

print("SalesGO ikonlar yaratildi:", os.listdir(OUT))
