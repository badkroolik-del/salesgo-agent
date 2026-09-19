"""SalesGO launcher ikon generatori (build vaqtida ishlaydi).
Yashil->ko'kish gradient rounded kvadrat + katta oq "S" + o'ng strelka +
pastda "SalesGO" (Sales oq, GO yashil). Foydalanuvchi bergan logo uslubida.
"""
import os
from PIL import Image, ImageDraw, ImageFont

SZ = 1024
OUT = "assets/icon"
os.makedirs(OUT, exist_ok=True)

C1 = (22, 163, 120)    # emerald-teal (yuqori)
C2 = (13, 108, 140)    # cyan-teal (past)
WHITE = (255, 255, 255, 255)
GREEN = (34, 197, 94, 255)   # GO yashil


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


def draw_logo(img, with_text=True):
    d = ImageDraw.Draw(img)
    cx = SZ / 2
    # ---- katta "S" ----
    s_px = int(SZ * (0.50 if with_text else 0.66))
    f = font(s_px)
    box = (0, 0, int(s_px * 0.6), s_px)
    try:
        box = d.textbbox((0, 0), "S", font=f)
    except Exception:
        pass
    sw = box[2] - box[0]
    sh = box[3] - box[1]
    sy = SZ * (0.30 if with_text else 0.24) - sh / 2
    sx = cx - sw / 2 - box[0]
    # yumshoq soya
    d.text((sx + SZ * 0.012, sy + SZ * 0.012 - box[1]), "S",
           font=f, fill=(0, 0, 0, 60))
    d.text((sx, sy - box[1]), "S", font=f, fill=WHITE)

    # ---- o'ng strelka (S ning yuqori-o'ngida) ----
    ay = SZ * (0.20 if with_text else 0.15)
    x0 = SZ * 0.50
    x1 = SZ * 0.72
    w = SZ * 0.050
    d.rounded_rectangle([x0, ay - w / 2, x1, ay + w / 2],
                        radius=w / 2, fill=WHITE)
    hh = SZ * 0.070
    d.polygon([(x1 - SZ * 0.01, ay - hh), (x1 + SZ * 0.095, ay),
               (x1 - SZ * 0.01, ay + hh)], fill=WHITE)

    # ---- "SalesGO" ----
    if with_text:
        tf = font(int(SZ * 0.15))
        try:
            ws = d.textlength("Sales", font=tf)
            wg = d.textlength("GO", font=tf)
            tb = d.textbbox((0, 0), "SalesGO", font=tf)
        except Exception:
            ws, wg, tb = SZ * 0.4, SZ * 0.2, (0, 0, 0, 0)
        tx = cx - (ws + wg) / 2
        ty = SZ * 0.80 - tb[1]
        d.text((tx, ty), "Sales", font=tf, fill=WHITE)
        d.text((tx + ws, ty), "GO", font=tf, fill=GREEN)


# ---- icon.png (to'liq: S + strelka + SalesGO) ----
base = gradient()
draw_logo(base, with_text=True)
icon = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
mask = Image.new("L", (SZ, SZ), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SZ, SZ],
                                       radius=int(SZ * 0.22), fill=255)
icon.paste(base, (0, 0), mask)
icon.save(os.path.join(OUT, "icon.png"))

# ---- foreground.png (adaptive: faqat S + strelka, matnsiz, markazda) ----
fg = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
draw_logo(fg, with_text=False)
fg.save(os.path.join(OUT, "foreground.png"))

print("SalesGO ikon (logo uslubi) yaratildi:", os.listdir(OUT))
