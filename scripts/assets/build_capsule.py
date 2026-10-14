# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Pack & Throw 的可重跑外層產線。

用途：用固定 seed 的 PIL 直接畫 7 種膠囊（TYPES）各一組空／裝車 512 x 512 RGB
atlas，呼叫 ``capsule_blender.py`` 建立共用 FBX、每張 atlas 一張圖示原圖與預覽，
再依 Knox Pass ``icon()`` 流程縮成 PZ 的 32 x 32 物品圖示。

用法（在 repo 根目錄執行）：
    uv run scripts/assets/build_capsule.py
    uv run scripts/assets/build_capsule.py --blender "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"

產物（<Id> 依序為 Cartoon、Real、Dust、Steam、SciFi、Magic、Shock）：
    MOD/MinidoracatPackThrowFor42/
      Contents/mods/MinidoracatPackThrowFor42/42/media/models_X/WorldItems/
        MinidoracatCapsule.fbx（7 種共用）
      .../media/textures/WorldItems/MinidoracatCapsule<Id>.png
      .../media/textures/WorldItems/MinidoracatCapsule<Id>Loaded.png
      .../media/textures/Item_MinidoracatCapsule<Id>.png
      .../media/textures/Item_MinidoracatCapsule<Id>Loaded.png
    舊的無 <Id> 檔名（MinidoracatCapsule[Loaded].png 兩組）每次執行都會刪掉。
    temp/assets-review/
      model_empty.png, model_loaded.png, side_neg_y.png, side_pos_y.png,
      ground_empty.png, ground_loaded.png（以上用 Cartoon），fbx_verify.txt,
      types_icons_4x.png（14 張圖示 1x/4x＋綠色盲模擬列）,
      types_vs_concept.png（與 docs/design/types/ 概念圖並排）

座標慣例：Blender 單位是公尺；膠囊平躺在地面，長軸沿 +X，原點是底面
中心（最低點 z=0，x/y 置中）。512 atlas 的 cylinder 矩形是圓周展開
（u＝繞 X 軸角度，v＝沿 +X）；兩側徽記中心由 config 的
``u_angle_offset``／``side_centers`` 固定，讓 child 端可讓 -Y 與 +Y
兩面都正向閱讀。

字型：scripts/assets/fonts/Barlow-SemiBold.ttf，
Barlow 的 SIL Open Font License 1.1；授權全文在
scripts/assets/fonts/OFL-Barlow.txt。圖像中唯一
烘入的文字是 ``07``，徽記的汽車剪影由本檔用 PIL 多邊形繪製。
"""

from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont


REPO = Path(__file__).resolve().parents[2]
MEDIA = REPO / "MOD/MinidoracatPackThrowFor42/Contents/mods/MinidoracatPackThrowFor42/42/media"
HERE = REPO / "scripts/assets"
BLENDER_DEFAULT = Path("C:/Program Files/Blender Foundation/Blender 5.2/blender.exe")
BLENDER_SCRIPT = HERE / "capsule_blender.py"
MODEL_TMP = REPO / "temp/assets-model"
REVIEW = REPO / "temp/assets-review"
FONT_BOLD = HERE / "fonts/Barlow-SemiBold.ttf"

ATLAS_SIZE = 512
SS = 4
SEED = 4207
BODY = (230, 228, 223)          # #e6e4df，暖白霧面
INK = (58, 59, 62)              # #3a3b3e
SEAM = (58, 59, 62)
# 7 種膠囊：(id, 主色 hex, 裝車環帶花紋, atlas 用色)。主色染在 +X（按鈕端）端蓋與環帶上。
# atlas 用色 = (端蓋色, 環帶色)，None 表示兩者都用主色。Real／Steam／Magic 的貼圖色比概念
# hex 亮（HSV 明度放大，色相不變），是為了補 3D 光照與 icon() 對比：32px 成品端蓋＋環帶的
# 平均相對亮度 L（linear Rec.709，取飽和度 > 0.3 的像素）要落在概念圖 L 的 ±15%。
# 端蓋同時影響空／裝車，裝車圖示的調色較暗，所以 Steam／Magic 的環帶比端蓋再亮一些。
# 成品/概念 L 比（調整前 → 後）：
#   Real   空 0.39 → 1.03、裝車 0.43 → 1.02（端蓋、環帶 x1.45）
#   Steam  空 0.82 → 1.00、裝車 0.58 → 0.96（端蓋 x1.1、環帶 x1.4）
#   Magic  空 1.04 → 1.04、裝車 0.70 → 0.88（端蓋 = hex、環帶 x1.4，V 封頂後降飽和）
TYPES = (
    ("Cartoon", (232, 116, 42), "solid", None),     # #E8742A
    ("Real", (110, 123, 59), "double", ((159, 178, 86), (159, 178, 86))),   # #6E7B3B
    ("Dust", (169, 128, 72), "twotone", None),      # #A98048
    ("Steam", (79, 127, 176), "rivets", ((87, 140, 194), (111, 178, 246))),  # #4F7FB0
    ("SciFi", (46, 197, 232), "glow", None),        # #2EC5E8
    ("Magic", (154, 90, 214), "sparkle", ((154, 90, 214), (194, 129, 255))),  # #9A5AD6
    ("Shock", (242, 194, 48), "hazard", None),      # #F2C230
)
STEEL_DARK = (141, 145, 150)    # #8d9196
STEEL_LIGHT = (185, 188, 192)   # #b9bcc0

# 與 capsule_blender.py 共用的像素矩形；x1/y1 是 exclusive。
ATLAS_RECTS = {
    "cylinder": [8, 8, 504, 252],
    "cap_minus": [8, 272, 192, 456],
    "cap_plus": [200, 272, 384, 456],
    "button": [392, 272, 504, 384],
    "seam": [400, 408, 432, 440],
    "button_side": [448, 408, 480, 440],
}
# 單一型號時期的檔名；Cartoon 改用 <Id> 檔名後每次建置都刪掉。
OLD_FILES = (
    MEDIA / "textures/WorldItems/MinidoracatCapsule.png",
    MEDIA / "textures/WorldItems/MinidoracatCapsuleLoaded.png",
    MEDIA / "textures/Item_MinidoracatCapsule.png",
    MEDIA / "textures/Item_MinidoracatCapsuleLoaded.png",
)


def _rgb_noise(im: Image.Image, rect: tuple[int, int, int, int], seed: int, amount: int = 3) -> None:
    """在指定 atlas 區塊加入固定 seed 的低對比使用痕跡。"""
    x0, y0, x1, y1 = rect
    px = im.load()
    rng = random.Random(seed)
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            n = rng.randint(-amount, amount)
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))


def _body_marks(d: ImageDraw.ImageDraw, rect: tuple[int, int, int, int], seed: int, ss: int = 1) -> None:
    """畫少量固定位置的刮痕與髒污；不使用透明像素。"""
    x0, y0, x1, y1 = rect
    rng = random.Random(seed)
    for _ in range(42):
        x = rng.randint(x0, x1 - 2)
        y = rng.randint(y0, y1 - 2)
        length = rng.randint(2, max(3, int((x1 - x0) * 0.035)))
        col = rng.choice(((205, 203, 198), (214, 212, 207), (218, 216, 210), (193, 191, 186)))
        d.line((x, y, min(x1 - 1, x + length), y + rng.choice((-1, 0, 1))), fill=col, width=max(1, ss))
    for _ in range(18):
        x = rng.randint(x0, x1 - 4)
        y = rng.randint(y0, y1 - 4)
        r = rng.randint(1, 3)
        d.ellipse((x, y, x + r, y + r), fill=(211, 209, 204))


def _car_mark(d: ImageDraw.ImageDraw, cx: float, cy: float, scale: float, ink: tuple[int, int, int]) -> None:
    """以多邊形畫原創簡潔轎車側面剪影。"""
    s = scale
    # 車身、車窗與兩個輪孔均為自畫幾何，不使用外部圖像。
    body = [(cx - 30 * s, cy + 8 * s), (cx - 23 * s, cy - 2 * s),
            (cx - 10 * s, cy - 5 * s), (cx - 3 * s, cy - 14 * s),
            (cx + 15 * s, cy - 14 * s), (cx + 25 * s, cy - 3 * s),
            (cx + 31 * s, cy + 2 * s), (cx + 31 * s, cy + 10 * s),
            (cx + 22 * s, cy + 10 * s), (cx + 19 * s, cy + 4 * s),
            (cx - 18 * s, cy + 4 * s), (cx - 21 * s, cy + 10 * s),
            (cx - 30 * s, cy + 10 * s)]
    d.polygon(body, fill=ink)
    d.polygon([(cx - 7 * s, cy - 11 * s), (cx + 2 * s, cy - 11 * s),
               (cx + 9 * s, cy - 3 * s), (cx - 12 * s, cy - 3 * s)], fill=(230, 228, 223))
    d.polygon([(cx + 4 * s, cy - 11 * s), (cx + 14 * s, cy - 11 * s),
               (cx + 22 * s, cy - 3 * s), (cx + 10 * s, cy - 3 * s)], fill=(230, 228, 223))
    for wx in (-18, 20):
        d.ellipse((cx + (wx - 5) * s, cy + 5 * s, cx + (wx + 5) * s, cy + 15 * s), fill=ink)
        d.ellipse((cx + (wx - 2) * s, cy + 8 * s, cx + (wx + 2) * s, cy + 12 * s), fill=(230, 228, 223))


def _draw_side_badge(im: Image.Image, center: tuple[int, int], seed: int,
                     flip_vertical: bool = False, flip_text_horizontal: bool = False) -> None:
    """畫側面徽記與 07。

    cylinder atlas 的 u 是圓周、v 是長軸，所以先以「沿膠囊長軸的水平
    標籤」畫，再旋轉 90 度放入 atlas。圓柱兩側的 u 方向相反；+Y 側
    還要上下翻轉，才能讓兩側投影後都保持字頂朝 +Z、車輪朝下；-Y
    側的 07 glyph 另在自身框內水平翻轉，避免整張 patch 翻轉而交換
    徽記與文字的長軸位置。
    """
    del seed  # 保留呼叫端的固定 seed 介面；圖形本身是確定性的。
    scale = SS
    pw, ph = 96 * scale, 54 * scale
    patch = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(patch)
    cx, cy = 25 * scale, 27 * scale
    radius = 21 * scale
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=INK + (255,), width=max(2, radius // 9))
    _car_mark(d, cx, cy - radius * 0.04, radius / 38.0, INK + (255,))
    font = ImageFont.truetype(str(FONT_BOLD), max(10, int(radius * 0.72)))
    text_pos = (56 * scale, cy)
    d.text(text_pos, "07", font=font, fill=INK + (255,), anchor="lm", stroke_width=0)
    if flip_text_horizontal:
        text_box = d.textbbox(text_pos, "07", font=font, anchor="lm", stroke_width=0)
        glyph = patch.crop(text_box).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        patch.paste((0, 0, 0, 0), text_box)
        patch.alpha_composite(glyph, text_box[:2])
    if flip_vertical:
        patch = patch.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    rotated = patch.rotate(90, expand=True, resample=Image.Resampling.BICUBIC)
    x = int(center[0] - rotated.width / 2)
    y = int(center[1] - rotated.height / 2)
    im.alpha_composite(rotated, (x, y))


def _radial_cap(im: Image.Image, rect: tuple[int, int, int, int], seed: int,
                base: tuple[int, int, int] = BODY) -> None:
    x0, y0, x1, y1 = rect
    px = im.load()
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    maxr = min(x1 - x0, y1 - y0) * 0.52
    rng = random.Random(seed)
    for y in range(y0, y1):
        for x in range(x0, x1):
            rr = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxr
            shade = int(max(-2, min(2, (0.5 - rr) * 3 + rng.choice((-1, 0, 0, 1)))))
            px[x, y] = tuple(max(0, min(255, c + shade)) for c in base)


# 這兩種花紋在圖示上是「發光」的：比 loaded 調色下的白殼還亮（概念圖如此）。
# 圖示另算一張只有花紋的無光照 pass，再以 lighter 疊回（見 capsule_blender.render_icon）。
EMISSIVE = ("glow", "sparkle")


def _band_overlay(hi: Image.Image, band: tuple[int, int, int, int], cyl: tuple[int, int, int, int],
                  pattern: str) -> Image.Image:
    """在 SS 倍解析的 atlas 上畫環帶的細節花紋（之後整張 LANCZOS 縮小 = 反鋸齒）。

    先畫進環帶大小的 patch 再貼回，花紋不會溢出環帶。圓周方向的間距一律
    以整個 cylinder 寬（u 0..1）均分，u=0/1 接縫處花紋連續。回傳 patch。
    """
    x0, y0 = band[0] * SS, band[1] * SS
    w, h = (band[2] + 1) * SS - x0, (band[3] + 1) * SS - y0
    circ = (cyl[2] - cyl[0]) * SS  # 圓周 u 0..1 的像素寬
    u0 = cyl[0] * SS - x0  # u=0 在 patch 座標的位置
    mid = h / 2
    patch = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(patch)
    if pattern == "rivets":
        p, r = circ / 12, 8 * SS
        for k in range(12):
            cx = u0 + (k + 0.5) * p
            d.ellipse((cx - r, mid - r, cx + r, mid + r), fill=(28, 34, 44, 255))
    elif pattern == "glow":
        d.rectangle((0, mid - 6 * SS, w, mid + 6 * SS), fill=(236, 252, 255, 255))
    elif pattern == "sparkle":
        rng = random.Random(SEED + 31)
        p, a, b = circ / 16, 13 * SS, 3 * SS
        for k in range(16):
            cx = u0 + (k + rng.uniform(0.3, 0.7)) * p
            cy = h * rng.uniform(0.15, 0.85)
            d.polygon([(cx, cy - a), (cx + b, cy - b), (cx + a, cy), (cx + b, cy + b),
                       (cx, cy + a), (cx - b, cy + b), (cx - a, cy), (cx - b, cy - b)], fill=(255, 251, 238, 255))
    elif pattern == "hazard":
        p = circ / 14
        for k in range(-int(h / p) - 2, 16):
            sx = u0 + k * p
            d.polygon([(sx, h), (sx + p / 2, h), (sx + p / 2 + h, 0), (sx + h, 0)], fill=(32, 30, 26, 255))
    hi.alpha_composite(patch, (x0, y0))
    return patch


def draw_atlas(path: Path, loaded: bool, ctype: tuple) -> Path | None:
    """畫一張不透明 512 RGB atlas；ctype 是 TYPES 的一列。

    發光花紋另寫一張黑底、只有花紋的 emit atlas 到 MODEL_TMP（不進 MOD），回傳其路徑。
    """
    _, colour, pattern, atlas_colours = ctype
    cap_colour, band_colour = atlas_colours or (colour, colour)
    im = Image.new("RGB", (ATLAS_SIZE, ATLAS_SIZE), BODY)
    d = ImageDraw.Draw(im)
    cyl = tuple(ATLAS_RECTS["cylinder"])
    cap_m = tuple(ATLAS_RECTS["cap_minus"])
    cap_p = tuple(ATLAS_RECTS["cap_plus"])
    d.rectangle(cyl, fill=BODY)
    _rgb_noise(im, cyl, SEED, 2)
    _body_marks(d, cyl, SEED + 1)
    _radial_cap(im, cap_m, SEED + 2)
    _radial_cap(im, cap_p, SEED + 3, cap_colour)
    _body_marks(d, cap_m, SEED + 4)
    _body_marks(d, cap_p, SEED + 5)

    # 裝車版多一條中段環帶（沿圓周全寬）；double／twotone 在 1x 就能畫，
    # 其餘花紋在高解析 pass 畫。
    band = (cyl[0] + 1, cyl[1] + 72, cyl[2] - 1, cyl[1] + 140)
    if loaded:
        d.rectangle(band, fill=band_colour)
        if pattern == "double":
            third = (band[3] - band[1]) / 3
            d.rectangle((band[0], round(band[1] + third), band[2], round(band[3] - third)), fill=BODY)
        elif pattern == "twotone":
            # v 向 +X（按鈕端），後半段明度 x0.62。
            dark = tuple(round(c * 0.62) for c in band_colour)
            d.rectangle((band[0], (band[1] + band[3] + 1) // 2, band[2], band[3]), fill=dark)
        _rgb_noise(im, band, SEED + 17, 2)
        _body_marks(d, band, SEED + 18)

    # cylinder 是 u＝圓周、v＝+X；兩個徽記放在 u=.25/.75 的 ±Y 外側，
    # 放在環帶之外，避免環帶蓋掉徽記與 07。高解析畫完再 LANCZOS 縮小。
    hi = im.resize((ATLAS_SIZE * SS, ATLAS_SIZE * SS), Image.Resampling.NEAREST).convert("RGBA")
    emit = None
    if loaded:
        patch = _band_overlay(hi, band, cyl, pattern)
        if pattern in EMISSIVE:
            emit = Image.new("RGB", hi.size, (0, 0, 0))
            emit.paste(patch, (band[0] * SS, band[1] * SS), patch)
    cy = (cyl[1] + 194) * SS
    # u=.25 是 +Y；u=.75 是 -Y。兩側的圓柱 UV 方向不同，不能共用
    # 同一張旋轉後的 patch。
    for u, flip_vertical, flip_text_horizontal in ((0.25, True, False), (0.75, False, True)):
        cx = int((cyl[0] + u * (cyl[2] - cyl[0])) * SS)
        _draw_side_badge(hi, (cx, int(cy)), SEED + int(u * 100),
                         flip_vertical=flip_vertical, flip_text_horizontal=flip_text_horizontal)
    # 另一端只有貼圖細線；按鈕端的深灰接縫由 child mesh 的 seam swatch 實體化。
    hd = ImageDraw.Draw(hi)
    hd.ellipse((cap_m[0] * SS + SS, cap_m[1] * SS + SS,
                cap_m[2] * SS - SS, cap_m[3] * SS - SS), outline=(218, 216, 211, 255), width=SS)
    im = hi.resize((ATLAS_SIZE, ATLAS_SIZE), Image.Resampling.LANCZOS).convert("RGB")

    # 色塊：按鈕以同心拉絲圈表現；button_side / seam 提供 child 端側面材質。
    bx0, by0, bx1, by1 = ATLAS_RECTS["button"]
    d = ImageDraw.Draw(im)
    d.rectangle((bx0, by0, bx1, by1), fill=STEEL_DARK)
    bcx, bcy = (bx0 + bx1) / 2, (by0 + by1) / 2
    for rr in range(min(bx1 - bx0, by1 - by0) // 2 - 2, 3, -3):
        t = (rr - 3) / max(1, (min(bx1 - bx0, by1 - by0) // 2 - 5))
        col = tuple(int(STEEL_LIGHT[i] * t + STEEL_DARK[i] * (1 - t)) for i in range(3))
        d.ellipse((bcx - rr, bcy - rr, bcx + rr, bcy + rr), outline=col, width=1)
    d.ellipse((bcx - 17, bcy - 17, bcx + 17, bcy + 17), fill=STEEL_LIGHT)
    for rr in range(15, 3, -2):
        col = (166 + (rr % 3) * 4, 169 + (rr % 3) * 4, 173 + (rr % 3) * 4)
        d.ellipse((bcx - rr, bcy - rr, bcx + rr, bcy + rr), outline=col, width=1)
    for key, col in (("seam", SEAM), ("button_side", (118, 122, 127))):
        x0, y0, x1, y1 = ATLAS_RECTS[key]
        d.rectangle((x0, y0, x1, y1), fill=col)
    im.save(path, format="PNG")
    if emit is None:
        return None
    emit_path = MODEL_TMP / f"emit_{path.stem}.png"
    emit.resize((ATLAS_SIZE, ATLAS_SIZE), Image.Resampling.LANCZOS).save(emit_path, format="PNG")
    return emit_path


def make_config(atlases: list[tuple[Path, bool, Path | None]], out: Path, review: Path, blender: Path) -> Path:
    """atlases：(atlas, loaded, emit atlas) 依 TYPES 順序空／裝車交錯；預覽算圖用第一組（Cartoon）。"""
    MODEL_TMP.mkdir(parents=True, exist_ok=True)
    config = {
        "repo": str(REPO),
        "media": str(MEDIA),
        "out": str(out),
        "review": str(review),
        "blender": str(blender),
        "atlas": {
            "empty": str(atlases[0][0]),
            "loaded": str(atlases[1][0]),
            "icons": [{"atlas": str(p), "loaded": loaded, "emit": emit and str(emit)} for p, loaded, emit in atlases],
            "size": ATLAS_SIZE,
            **ATLAS_RECTS,
        },
        "seed": SEED,
        "geometry": {
            "length": 0.070,
            "diameter": 0.027,
            "axis": "+X",
            "origin": "bottom_center",
            "cylinder_u_angle_offset": 1.5707963267948966,
            "side_centers": {"minus_y": 0.25, "plus_y": 0.75},
            "model_scale": 3.0,
        },
        "render": {
            "icon": [256, 256],
            "model": [1024, 768],
            "ground": [512, 512],
            "ground_pixels_per_meter": 90.5,
            "background": "#1E1F22",
        },
    }
    cfg = MODEL_TMP / "config.json"
    cfg.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return cfg


def icon(src: Path, dst: Path) -> None:
    """Knox Pass 的 icon()：裁切、28 px、alpha 二值化、1 px 外框。"""
    im = Image.open(src).convert("RGBA")
    bbox = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if bbox is None:
        raise AssertionError(f"Blender icon 無透明以外內容：{src}")
    im = im.crop(bbox)
    scale = 28.0 / max(im.size)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.Resampling.LANCZOS)
    alpha = im.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    im = ImageEnhance.Sharpness(ImageEnhance.Color(ImageEnhance.Contrast(im.convert("RGB")).enhance(1.35)).enhance(1.3)).enhance(1.4)
    im.putalpha(alpha)
    canvas = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    canvas.paste(im, ((32 - im.width) // 2, (32 - im.height) // 2), im)
    ring = canvas.getchannel("A").filter(ImageFilter.MaxFilter(3))
    outline = Image.new("RGBA", (32, 32), (28, 26, 24, 255))
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.paste(outline, (0, 0), ring)
    out.paste(canvas, (0, 0), canvas.getchannel("A"))
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, format="PNG")


# Machado, Oliveira & Fernandes 2009，deuteranopia severity 1.0；作用在 linear RGB。
DEUTERANOPIA = ((0.367322, 0.860646, -0.227968),
                (0.280085, 0.672501, 0.047413),
                (-0.011820, 0.042940, 0.968881))
_TO_LINEAR = [c / 255 / 12.92 if c <= 10 else ((c / 255 + 0.055) / 1.055) ** 2.4 for c in range(256)]


def _to_srgb(v: float) -> int:
    v = min(1.0, max(0.0, v))
    return round(255 * (v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055))


def deuteranopia(im: Image.Image) -> Image.Image:
    out = im.convert("RGBA")
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            lin = (_TO_LINEAR[r], _TO_LINEAR[g], _TO_LINEAR[b])
            px[x, y] = tuple(_to_srgb(sum(m * c for m, c in zip(row, lin))) for row in DEUTERANOPIA) + (a,)
    return out


def make_type_reviews(icons: list[Path]) -> None:
    """types_icons_4x.png：14 張圖示 1x／4x＋裝車版綠色盲模擬；
    types_vs_concept.png：每種的概念圖與成品（空、裝車、綠色盲）4x 並排。"""
    bg, ink = (45, 46, 49, 255), (225, 225, 225, 255)
    font = ImageFont.truetype(str(FONT_BOLD), 18)
    big = lambda im: im.resize((128, 128), Image.Resampling.NEAREST)  # noqa: E731
    final = {t[0]: [Image.open(p).convert("RGBA") for p in icons[i * 2:i * 2 + 2]] for i, t in enumerate(TYPES)}

    col = 148
    sheet = Image.new("RGBA", (16 + col * len(TYPES), 36 + 48 + 3 * 140 + 24), bg)
    d = ImageDraw.Draw(sheet)
    for c, (tid, _, pattern, _) in enumerate(TYPES):
        x = 16 + c * col
        empty, loaded = final[tid]
        deut = deuteranopia(loaded)
        d.text((x, 10), f"{tid} ({pattern})", font=font, fill=ink)
        for k, im in enumerate((empty, loaded, deut)):  # 1x：空、裝車、裝車綠色盲
            sheet.alpha_composite(im, (x + k * 44, 40))
        for r, im in enumerate((empty, loaded, deut)):  # 4x 三列，同順序
            sheet.alpha_composite(big(im), (x, 84 + r * 140))
    d.text((16, sheet.height - 22), "rows 4x: empty / loaded / loaded deuteranopia (Machado 2009, sev 1, linear RGB)",
           font=font, fill=ink)
    sheet.save(REVIEW / "types_icons_4x.png", format="PNG")

    concept_dir = REPO / "docs/design/types"
    heads = ("concept empty", "final empty", "concept loaded", "final loaded", "concept deut", "final deut")
    sheet = Image.new("RGBA", (120 + 140 * len(heads), 36 + 140 * len(TYPES)), bg)
    d = ImageDraw.Draw(sheet)
    for k, head in enumerate(heads):
        d.text((120 + k * 140, 10), head, font=font, fill=ink)
    for r, (tid, *_) in enumerate(TYPES):
        y = 36 + r * 140
        empty, loaded = final[tid]
        concept = [Image.open(concept_dir / f"{tid}-{s}.png").convert("RGBA") for s in ("empty", "loaded", "loaded-deut")]
        d.text((12, y + 54), tid, font=font, fill=ink)
        for k, im in enumerate((concept[0], empty, concept[1], loaded, concept[2], deuteranopia(loaded))):
            sheet.alpha_composite(big(im), (120 + k * 140, y))
    sheet.save(REVIEW / "types_vs_concept.png", format="PNG")


def _check_png(path: Path, size: tuple[int, int], mode: str | None = None) -> Image.Image:
    if not path.is_file():
        raise AssertionError(f"缺少產物：{path}")
    im = Image.open(path)
    if im.size != size:
        raise AssertionError(f"尺寸錯誤 {path}: {im.size} != {size}")
    if mode is not None and im.mode != mode:
        raise AssertionError(f"色彩模式錯誤 {path}: {im.mode} != {mode}")
    return im


def validate_outputs(atlases: list[Path], icons: list[Path], fbx: Path) -> None:
    if len(atlases) != 2 * len(TYPES) or len(icons) != 2 * len(TYPES):
        raise AssertionError(f"atlas／圖示數量錯誤：{len(atlases)}／{len(icons)}")
    images = [_check_png(p, (ATLAS_SIZE, ATLAS_SIZE), "RGB") for p in atlases]
    images += [_check_png(p, (32, 32), "RGBA") for p in icons]
    # PNG metadata 不得偷偷帶入品牌／文字；畫面文字只由上方固定的 "07" 繪製。
    forbidden_text = ("capsule corporation", "hoi-poi", "七龍珠")
    for im in images:
        metadata = " ".join(str(v).lower() for v in im.info.values())
        assert not any(word in metadata for word in forbidden_text), "PNG metadata 含禁止文字"
    for p in (fbx, REVIEW / "fbx_verify.txt", REVIEW / "model_empty.png", REVIEW / "model_loaded.png",
              REVIEW / "side_neg_y.png", REVIEW / "side_pos_y.png", REVIEW / "ground_empty.png",
              REVIEW / "ground_loaded.png", REVIEW / "types_icons_4x.png", REVIEW / "types_vs_concept.png"):
        if not p.is_file() or p.stat().st_size == 0:
            raise AssertionError(f"缺少或空白產物：{p}")
    _check_png(REVIEW / "model_empty.png", (1024, 768))
    _check_png(REVIEW / "model_loaded.png", (1024, 768))
    _check_png(REVIEW / "side_neg_y.png", (800, 400))
    _check_png(REVIEW / "side_pos_y.png", (800, 400))
    stale = [p for p in OLD_FILES if p.exists()]
    if stale:
        raise AssertionError(f"舊檔名仍在：{stale}")
    # 不允許 MOD 產生 Blender 暫存檔；本產線只寫一個 FBX 與 28 張指定 PNG。
    forbidden = [p for p in MEDIA.rglob("*") if p.is_file() and p.suffix.lower() in {".blend", ".blend1"}]
    if forbidden:
        raise AssertionError(f"MOD 內不應有 Blender 暫存檔：{forbidden}")
    if not fbx.name.endswith(".fbx"):
        raise AssertionError(f"FBX 路徑錯誤：{fbx}")


def run(args: argparse.Namespace) -> None:
    blender = Path(args.blender).resolve()
    if not blender.is_file():
        raise FileNotFoundError(f"找不到 Blender：{blender}")
    if not BLENDER_SCRIPT.is_file():
        raise FileNotFoundError(f"找不到 Blender child 腳本：{BLENDER_SCRIPT}")

    texture_dir = MEDIA / "textures/WorldItems"
    model_dir = MEDIA / "models_X/WorldItems"
    texture_dir.mkdir(parents=True, exist_ok=True)
    model_dir.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    out = MODEL_TMP / "blender-out"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    atlases = []
    for ctype in TYPES:
        for loaded in (False, True):
            path = texture_dir / f"MinidoracatCapsule{ctype[0]}{'Loaded' if loaded else ''}.png"
            atlases.append((path, loaded, draw_atlas(path, loaded, ctype)))
    config = make_config(atlases, out, REVIEW, blender)

    cmd = [str(blender), "-b", "--factory-startup", "--python", str(BLENDER_SCRIPT), "--", str(config)]
    print("blender ->", " ".join(cmd))
    proc = subprocess.run(cmd, cwd=str(REPO), capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.stdout:
        print(proc.stdout[-12000:])
    if proc.stderr:
        print(proc.stderr[-12000:], file=sys.stderr)
    if proc.returncode != 0:
        raise RuntimeError(f"Blender 產線失敗（exit {proc.returncode}）")

    # child 端每張 atlas 產出 out/icon_<atlas stem>.png（256px 透明算圖），發光花紋另有
    # icon_<stem>_emit.png（無光照、只有花紋）；以 lighter 疊回後縮成 MOD 物品圖示。
    icons = []
    for atlas, _, emit in atlases:
        src = out / f"icon_{atlas.stem}.png"
        _check_png(src, (256, 256))
        if emit:
            lit = Image.open(src).convert("RGBA")
            glow = Image.open(out / f"icon_{atlas.stem}_emit.png").convert("RGB")
            merged = ImageChops.lighter(lit.convert("RGB"), glow)
            merged.putalpha(lit.getchannel("A"))
            merged.save(src, format="PNG")
        icons.append(dst := MEDIA / f"textures/Item_{atlas.stem}.png")
        icon(src, dst)
    for old in OLD_FILES:
        old.unlink(missing_ok=True)
    make_type_reviews(icons)

    fbx = model_dir / "MinidoracatCapsule.fbx"
    validate_outputs([a for a, _, _ in atlases], icons, fbx)
    print("BUILD OK ->", MEDIA)
    print("review ->", REVIEW)


def main() -> None:
    ap = argparse.ArgumentParser(description="建立 Pack & Throw 的 atlas、FBX、PZ 物品圖示與預覽")
    ap.add_argument("--blender", default=str(BLENDER_DEFAULT), help="Blender 5.2 可執行檔絕對路徑")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
