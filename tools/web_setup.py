"""`flutter create --platforms=web` dan keyin web versiyani brendga moslash (CI da ishlaydi).

- sarlavha/manifest: «SalesGO SFA», firma ranglari
- favicon va ikonkalar: assets/icon/icon.png (asl SalesGO belgisi) dan
"""
import json
import os
import re
import sys

NAME = "SalesGO SFA"
DESC = "SalesGO SFA — agent, dostavka, inkassator va supervayzer ilovasi (brauzer versiyasi)"
NAVY = "#02255B"

root = sys.argv[1] if len(sys.argv) > 1 else "."
web = os.path.join(root, "web")

p = os.path.join(web, "index.html")
s = open(p, encoding="utf-8").read()
s = re.sub(r"<title>.*?</title>", f"<title>{NAME}</title>", s, flags=re.S)
s = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{DESC}">', s)
s = re.sub(r'<meta name="apple-mobile-web-app-title" content="[^"]*">', f'<meta name="apple-mobile-web-app-title" content="{NAME}">', s)
if 'name="theme-color"' not in s:
    s = s.replace("<head>", f'<head>\n  <meta name="theme-color" content="{NAVY}">', 1)
open(p, "w", encoding="utf-8").write(s)

p = os.path.join(web, "manifest.json")
m = json.load(open(p, encoding="utf-8"))
m.update(name=NAME, short_name="SalesGO", description=DESC, background_color="#FFFFFF", theme_color=NAVY)
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=4)

try:
    from PIL import Image
    src = Image.open(os.path.join(root, "assets", "icon", "icon.png")).convert("RGBA")
    fg = Image.open(os.path.join(root, "assets", "icon", "foreground.png")).convert("RGBA")
    src.resize((64, 64), Image.LANCZOS).save(os.path.join(web, "favicon.png"))
    for n in (192, 512):
        src.resize((n, n), Image.LANCZOS).save(os.path.join(web, "icons", f"Icon-{n}.png"))
        fg.resize((n, n), Image.LANCZOS).save(os.path.join(web, "icons", f"Icon-maskable-{n}.png"))
    print("web ikonkalar yangilandi")
except Exception as e:  # ikonka bo'lmasa ham build davom etadi
    print("web ikonka o'tkazib yuborildi:", e)
print("web patched")
