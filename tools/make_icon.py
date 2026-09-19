"""SalesGO launcher ikon generatori (build vaqtida ishlaydi).
Yashil-havorang gradient rounded kvadrat + "SalesGO" yozuvi (GO sariq).
"""
import os
from PIL import Image, ImageDraw, ImageFont

SZ = 1024
OUT = "assets/icon"
os.makedirs(OUT, exist_ok=True)

C1 = (16, 185, 129)   # emerald
C2 = (6, 182, 212)    # cyan
WHITE = (255, 255, 255, 255)
GO = (249, 115, 22, 255)  # orange


def font(px):
    for p in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def gradient():
    g = Image.new("RGB", (SZ, SZ), C1)
    dr = ImageDraw.Draw(g)
    for y in range(SZ):
        t = y / SZ
        col = tuple(int(C1[i] + (C2[i] - C1[i]) * t) for i in range(3))
        dr.line([(0, y), (SZ, y)], fill=col)
    return g


def draw_wordmark(img, scale):
    d = ImageDraw.Draw(img)
    target_w = SZ * scale
    px = int(SZ * 0.26)
    f = font(px)
    while px > 24:
        try:
            ws = d.textlength("Sales", font=f)
            wg = d.textlength("GO", font=f)
        except Exception:
            ws, wg = target_w, 0
        if ws + wg <= target_w:
            break
        px -= 8
        f = font(px)
    try:
        ws = d.textlength("Sales", font=f)
        wg = d.textlength("GO", font=f)
        box = d.textbbox((0, 0), "SalesGO", font=f)
        h = box[3] - box[1]
        x = (SZ - (ws + wg)) / 2
        y = (SZ - h) / 2 - box[1]
        d.text((x, y), "Sales", font=f, fill=WHITE)
        d.text((x + ws, y), "GO", font=f, fill=GO)
    except Exception:
        d.text((SZ * 0.1, SZ * 0.4), "SalesGO", font=f, fill=WHITE)


# ---- icon.png ----
icon = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
mask = Image.new("L", (SZ, SZ), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SZ, SZ], radius=int(SZ * 0.22), fill=255)
icon.paste(gradient(), (0, 0), mask)
draw_wordmark(icon, 0.80)
icon.save(os.path.join(OUT, "icon.png"))

# ---- foreground.png (adaptive) ----
fg = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
draw_wordmark(fg, 0.62)
fg.save(os.path.join(OUT, "foreground.png"))

print("SalesGO ikonlar (wordmark) yaratildi:", os.listdir(OUT))
