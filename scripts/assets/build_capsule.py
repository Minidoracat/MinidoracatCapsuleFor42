# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Vehicle Capsule 的可重跑外層產線。

用途：用固定 seed 的 PIL 直接畫兩張 512 x 512 RGB atlas，呼叫
``capsule_blender.py`` 建立共用 FBX、圖示原圖與預覽，再依 Knox Pass
``icon()`` 流程縮成 PZ 的 32 x 32 物品圖示。

用法（在 repo 根目錄執行）：
    uv run scripts/assets/build_capsule.py
    uv run scripts/assets/build_capsule.py --blender "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"

產物：
    D:/github/MinidoracatVehicleCapsuleFor42/MOD/MinidoracatVehicleCapsuleFor42/
      Contents/mods/MinidoracatVehicleCapsuleFor42/42/media/models_X/WorldItems/
        MinidoracatVehicleCapsule.fbx
      .../media/textures/WorldItems/MinidoracatVehicleCapsule.png
      .../media/textures/WorldItems/MinidoracatVehicleCapsuleLoaded.png
      .../media/textures/Item_MinidoracatVehicleCapsule.png
      .../media/textures/Item_MinidoracatVehicleCapsuleLoaded.png
    D:/github/MinidoracatVehicleCapsuleFor42/temp/assets-review/
      model_empty.png, model_loaded.png, side_neg_y.png, side_pos_y.png,
      ground_empty.png, ground_loaded.png, icons_4x.png, fbx_verify.txt

座標慣例：Blender 單位是公尺；膠囊平躺在地面，長軸沿 +X，原點是底面
中心（最低點 z=0，x/y 置中）。512 atlas 的 cylinder 矩形是圓周展開
（u＝繞 X 軸角度，v＝沿 +X）；兩側徽記中心由 config 的
``u_angle_offset``／``side_centers`` 固定，讓 child 端可讓 -Y 與 +Y
兩面都正向閱讀。

字型：D:/github/MinidoracatVehicleCapsuleFor42/scripts/assets/fonts/Barlow-SemiBold.ttf，
Barlow 的 SIL Open Font License 1.1；授權全文在
D:/github/MinidoracatVehicleCapsuleFor42/scripts/assets/fonts/OFL-Barlow.txt。圖像中唯一
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

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


REPO = Path("D:/github/MinidoracatVehicleCapsuleFor42")
MEDIA = REPO / "MOD/MinidoracatVehicleCapsuleFor42/Contents/mods/MinidoracatVehicleCapsuleFor42/42/media"
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
ORANGE = (232, 116, 42)         # #E8742A
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


def _radial_cap(im: Image.Image, rect: tuple[int, int, int, int], seed: int) -> None:
    x0, y0, x1, y1 = rect
    px = im.load()
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    maxr = min(x1 - x0, y1 - y0) * 0.52
    rng = random.Random(seed)
    for y in range(y0, y1):
        for x in range(x0, x1):
            rr = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxr
            shade = int(max(-2, min(2, (0.5 - rr) * 3 + rng.choice((-1, 0, 0, 1)))))
            px[x, y] = tuple(max(0, min(255, c + shade)) for c in BODY)


def draw_atlas(path: Path, loaded: bool) -> None:
    """畫一張不透明 512 RGB atlas。"""
    im = Image.new("RGB", (ATLAS_SIZE, ATLAS_SIZE), BODY)
    d = ImageDraw.Draw(im)
    cyl = tuple(ATLAS_RECTS["cylinder"])
    cap_m = tuple(ATLAS_RECTS["cap_minus"])
    cap_p = tuple(ATLAS_RECTS["cap_plus"])
    d.rectangle(cyl, fill=BODY)
    _rgb_noise(im, cyl, SEED, 2)
    _body_marks(d, cyl, SEED + 1)
    _radial_cap(im, cap_m, SEED + 2)
    _radial_cap(im, cap_p, SEED + 3)
    _body_marks(d, cap_m, SEED + 4)
    _body_marks(d, cap_p, SEED + 5)

    # 裝車版只多這條中段橘色環帶（沿圓周全寬），其餘像素來源相同。
    if loaded:
        band = (cyl[0] + 1, cyl[1] + 72, cyl[2] - 1, cyl[1] + 140)
        d.rectangle(band, fill=ORANGE)
        _rgb_noise(im, band, SEED + 17, 2)
        _body_marks(d, band, SEED + 18)

    # cylinder 是 u＝圓周、v＝+X；兩個徽記放在 u=.25/.75 的 ±Y 外側，
    # 放在橘帶之外，避免環帶蓋掉徽記與 07。高解析畫完再 LANCZOS 縮小。
    hi = im.resize((ATLAS_SIZE * SS, ATLAS_SIZE * SS), Image.Resampling.NEAREST).convert("RGBA")
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


def make_config(empty_atlas: Path, loaded_atlas: Path, out: Path, review: Path, blender: Path) -> Path:
    MODEL_TMP.mkdir(parents=True, exist_ok=True)
    config = {
        "repo": str(REPO),
        "media": str(MEDIA),
        "out": str(out),
        "review": str(review),
        "blender": str(blender),
        "atlas": {
            "empty": str(empty_atlas),
            "loaded": str(loaded_atlas),
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


def make_icon_review(empty: Path, loaded: Path, dst: Path) -> None:
    """將兩張 32 px 圖示與 NEAREST 4x 版本上下排列，便於人工比較。"""
    a, b = Image.open(empty).convert("RGBA"), Image.open(loaded).convert("RGBA")
    canvas = Image.new("RGBA", (320, 160), (45, 46, 49, 255))
    # 1x row：兩張並排；4x row：兩張各 128 px 並排。
    canvas.alpha_composite(a, (72, 12))
    canvas.alpha_composite(b, (216, 12))
    canvas.alpha_composite(a.resize((128, 128), Image.Resampling.NEAREST), (16, 28))
    canvas.alpha_composite(b.resize((128, 128), Image.Resampling.NEAREST), (176, 28))
    dst.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dst, format="PNG")


def _check_png(path: Path, size: tuple[int, int], mode: str | None = None) -> Image.Image:
    if not path.is_file():
        raise AssertionError(f"缺少產物：{path}")
    im = Image.open(path)
    if im.size != size:
        raise AssertionError(f"尺寸錯誤 {path}: {im.size} != {size}")
    if mode is not None and im.mode != mode:
        raise AssertionError(f"色彩模式錯誤 {path}: {im.mode} != {mode}")
    return im


def validate_outputs(empty_atlas: Path, loaded_atlas: Path, empty_icon: Path, loaded_icon: Path, fbx: Path) -> None:
    images = [
        _check_png(empty_atlas, (ATLAS_SIZE, ATLAS_SIZE), "RGB"),
        _check_png(loaded_atlas, (ATLAS_SIZE, ATLAS_SIZE), "RGB"),
        _check_png(empty_icon, (32, 32), "RGBA"),
        _check_png(loaded_icon, (32, 32), "RGBA"),
    ]
    # PNG metadata 不得偷偷帶入品牌／文字；畫面文字只由上方固定的 "07" 繪製。
    forbidden_text = ("capsule corporation", "hoi-poi", "七龍珠")
    for im in images:
        metadata = " ".join(str(v).lower() for v in im.info.values())
        assert not any(word in metadata for word in forbidden_text), "PNG metadata 含禁止文字"
    for p in (fbx, REVIEW / "fbx_verify.txt", REVIEW / "model_empty.png", REVIEW / "model_loaded.png",
              REVIEW / "side_neg_y.png", REVIEW / "side_pos_y.png", REVIEW / "ground_empty.png",
              REVIEW / "ground_loaded.png", REVIEW / "icons_4x.png"):
        if not p.is_file() or p.stat().st_size == 0:
            raise AssertionError(f"缺少或空白產物：{p}")
    _check_png(REVIEW / "model_empty.png", (1024, 768))
    _check_png(REVIEW / "model_loaded.png", (1024, 768))
    _check_png(REVIEW / "side_neg_y.png", (800, 400))
    _check_png(REVIEW / "side_pos_y.png", (800, 400))
    # 不允許 MOD 產生 Blender 暫存檔；本產線只寫一個 FBX 與四張指定 PNG。
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

    empty_atlas = texture_dir / "MinidoracatVehicleCapsule.png"
    loaded_atlas = texture_dir / "MinidoracatVehicleCapsuleLoaded.png"
    draw_atlas(empty_atlas, loaded=False)
    draw_atlas(loaded_atlas, loaded=True)
    config = make_config(empty_atlas, loaded_atlas, out, REVIEW, blender)

    cmd = [str(blender), "-b", "--factory-startup", "--python", str(BLENDER_SCRIPT), "--", str(config)]
    print("blender ->", " ".join(cmd))
    proc = subprocess.run(cmd, cwd=str(REPO), capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.stdout:
        print(proc.stdout[-12000:])
    if proc.stderr:
        print(proc.stderr[-12000:], file=sys.stderr)
    if proc.returncode != 0:
        raise RuntimeError(f"Blender 產線失敗（exit {proc.returncode}）")

    # child 端以 config out/icon_*.png 產出 256px 透明算圖，這裡縮成 MOD 物品圖示。
    _check_png(out / "icon_empty.png", (256, 256))
    _check_png(out / "icon_loaded.png", (256, 256))
    icon(empty_icon := out / "icon_empty.png", MEDIA / "textures/Item_MinidoracatVehicleCapsule.png")
    icon(loaded_icon := out / "icon_loaded.png", MEDIA / "textures/Item_MinidoracatVehicleCapsuleLoaded.png")
    make_icon_review(MEDIA / "textures/Item_MinidoracatVehicleCapsule.png",
                     MEDIA / "textures/Item_MinidoracatVehicleCapsuleLoaded.png", REVIEW / "icons_4x.png")

    fbx = model_dir / "MinidoracatVehicleCapsule.fbx"
    validate_outputs(empty_atlas, loaded_atlas, MEDIA / "textures/Item_MinidoracatVehicleCapsule.png",
                     MEDIA / "textures/Item_MinidoracatVehicleCapsuleLoaded.png", fbx)
    print("BUILD OK ->", MEDIA)
    print("review ->", REVIEW)


def main() -> None:
    ap = argparse.ArgumentParser(description="建立 Vehicle Capsule 的 atlas、FBX、PZ 物品圖示與預覽")
    ap.add_argument("--blender", default=str(BLENDER_DEFAULT), help="Blender 5.2 可執行檔絕對路徑")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
