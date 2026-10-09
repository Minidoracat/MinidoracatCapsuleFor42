# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""素材對照圖（人看的，不進 MOD）：兩個模型的 Blender 算圖、遊戲投影、32x32 圖示 1x／4x、8 幀煙霧。

先跑 build_capsule.py 與 build_smoke.py，再在 repo 根執行：
    uv run scripts/assets/review_sheet.py
產物：temp/assets-review/review.png
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
REVIEW = os.path.join(REPO, "temp", "assets-review")
TEX = os.path.join(REPO, "MOD", "MinidoracatVehicleCapsuleFor42", "Contents", "mods", "MinidoracatVehicleCapsuleFor42",
                   "42", "media", "textures")
FONT = ImageFont.truetype(os.path.join(HERE, "fonts", "Barlow-SemiBold.ttf"), 22)
BG, PANEL, INK = (30, 31, 34), (96, 100, 96), (225, 225, 225)


def fit(im, box):
    im = im.copy()
    im.thumbnail(box, Image.LANCZOS)
    return im


def main():
    W = 1600
    renders = [Image.open(os.path.join(REVIEW, f"model_{k}.png")).convert("RGBA") for k in ("empty", "loaded")]
    ground = [Image.open(os.path.join(REVIEW, f"ground_{k}.png")).convert("RGBA") for k in ("empty", "loaded")]
    icons = [Image.open(os.path.join(TEX, f"Item_MinidoracatVehicleCapsule{s}.png")).convert("RGBA") for s in ("", "Loaded")]
    smoke = [Image.open(os.path.join(TEX, "MinidoracatVehicleCapsule", f"smoke_{i}.png")).convert("RGBA") for i in range(1, 9)]
    sheet = Image.new("RGB", (W, 1460), BG)
    d = ImageDraw.Draw(sheet)

    d.text((20, 14), "Blender render: empty / loaded", font=FONT, fill=INK)
    for i, im in enumerate(renders):
        im = fit(im, (780, 585))
        sheet.paste(im, (20 + i * 790, 50), im)

    y = 660
    d.text((20, y), "Game projection (az 45, el 30, 1 m = 90.5 px, model scale 3.0), x1 and x4", font=FONT, fill=INK)
    x = 20
    for im in ground:
        for k in (1, 4):
            g = im.crop(im.getbbox()) if im.getbbox() else im
            g = g.resize((g.width * k, g.height * k), Image.NEAREST)
            tile = Image.new("RGB", (max(g.width + 20, 60), g.height + 20), PANEL)
            tile.paste(g, (10, 10), g)
            sheet.paste(tile, (x, y + 40))
            x += tile.width + 20
        x += 40

    y = 900
    d.text((20, y), "Icons 32x32: x1 and x4 (nearest)", font=FONT, fill=INK)
    x = 20
    for im in icons:
        for k in (1, 4):
            tile = Image.new("RGB", (32 * k + 20, 32 * k + 20), PANEL)
            big = im.resize((32 * k, 32 * k), Image.NEAREST)
            tile.paste(big, (10, 10), big)
            sheet.paste(tile, (x, y + 40))
            x += tile.width + 20
        x += 40

    y = 1090
    d.text((20, y), "Smoke frames 1-8 (256 px, shown at 180 px on grey and on white)", font=FONT, fill=INK)
    for i, im in enumerate(smoke):
        f = im.resize((180, 180), Image.LANCZOS)
        for row, bg in enumerate((PANEL, (235, 235, 230))):
            tile = Image.new("RGB", (190, 120 if row else 190), bg)
            if row:  # 白底小版：遊戲裡縮小顯示時的樣子
                s = f.resize((96, 96), Image.LANCZOS)
                tile.paste(s, (47, 12), s)
            else:
                tile.paste(f, (5, 5), f)
            sheet.paste(tile, (20 + i * 196, y + 40 + row * 196))
    out = os.path.join(REVIEW, "review.png")
    sheet.save(out)
    print("review ->", out)


if __name__ == "__main__":
    main()
