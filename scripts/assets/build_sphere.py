# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""帕魯球（MinidoracatSphere）的可重跑產線；慣例照 build_capsule.py。

用 PIL 畫四級（TIERS）各一組空／裝了動物的 512 x 512 RGB atlas，呼叫 ``sphere_blender.py``
建共用 FBX、圖示原圖與預覽，再用 build_capsule 的 ``icon()`` 縮成 PZ 的 32 x 32 物品圖示。

用法（在 repo 根目錄執行）：
    uv run scripts/assets/build_sphere.py [--blender <blender.exe>]

產物：
    media/models_X/WorldItems/MinidoracatSphere.fbx（四級共用）
    media/textures/WorldItems/MinidoracatSphere<Tier>[Loaded].png
    media/textures/Item_MinidoracatSphere<Tier>[Loaded].png
    temp/sphere-art/sheet.png（四級 × 空／裝了：圖示 1x、4x、EEVEE 世界模型）、fbx_verify.txt

atlas：glass 矩形是玻璃球的經緯展開（u＝繞 X 軸角度 θ，θ=0 朝 -Z、θ=π 朝 +Z；v＝從 -X 極
起的極角 φ/π）；brass 是尖頂旋轉面（u＝繞軸、v＝沿輪廓弧長）；ornament 是頂端飾片的徑向貼圖。
圖示都疊一張無光照的 emit pass（lighter）：空的是朝圖示相機的本色球心光（發光玻璃），裝了的
球心再一團近白熱點＋大光點；世界貼圖裝了的玻璃更亮、赤道一圈亮帶與白色光點。32 px 下一眼分得出。
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from build_capsule import BLENDER_DEFAULT, FONT_BOLD, MEDIA, REPO, _check_png, icon  # noqa: E402

BLENDER_SCRIPT = HERE / "sphere_blender.py"
WORK = REPO / "temp/sphere-art"
ATLAS = 512
SS = 4
SEED = 4242
TIERS = (
    ("Basic", (38, 140, 235)),    # 藍
    ("Mega", (40, 190, 100)),     # 綠
    ("Giga", (250, 226, 40)),     # 黃（偏檸檬黃，跟黃銅框分得開）
    ("Legend", (165, 60, 225)),   # 紫
)
BRASS = (196, 150, 58)
BRASS_LIGHT = (246, 214, 120)
BRASS_DARK = (92, 62, 22)
# 與 sphere_blender.py 共用的像素矩形；x1/y1 exclusive。
RECTS = {"glass": [0, 0, 512, 320], "brass": [8, 336, 248, 504], "ornament": [264, 336, 424, 496]}
GW, GH = 512, 320
ICON_VIEW = {"az": 80, "el": 65, "roll": -32}
BAND_W = 11  # 黃銅框寬（1x atlas px）


def direction(u: float, v: float) -> tuple[float, float, float]:
    """glass 的 (u, v) → 球面單位向量，與 sphere_blender 的頂點公式一致。"""
    th, ph = 2 * math.pi * u, math.pi * v
    return (-math.cos(ph), math.sin(ph) * math.sin(th), -math.sin(ph) * math.cos(th))


def to_uv(p: tuple[float, float, float]) -> tuple[float, float]:
    x, y, z = p
    ph = math.acos(max(-1.0, min(1.0, -x)))
    th = math.atan2(y, -z) % (2 * math.pi)
    return th / (2 * math.pi), ph / math.pi


def _polyline(d: ImageDraw.ImageDraw, pts: list[tuple[float, float]], fill, width: int) -> None:
    """atlas 座標（1x）折線，畫在 SS 倍畫布；跨 u 接縫處斷開並在兩側各畫一次。"""
    seg = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        if abs(b[0] - a[0]) > GW / 2:
            _draw(d, seg, fill, width)
            seg = []
        seg.append(b)
    _draw(d, seg, fill, width)


def _draw(d, seg, fill, width):
    if len(seg) < 2:
        return
    for off in (-GW, 0, GW):
        d.line([((x + off) * SS, y * SS) for x, y in seg], fill=fill, width=width * SS, joint="curve")


def _cage() -> list[list[tuple[float, float]]]:
    """黃銅框的折線（1x atlas 座標）：兩條過頂端飾片的斜大圓、兩極旁的緯線環、六個漩渦。"""
    paths = []
    for alpha in (math.radians(28), math.radians(-62)):
        a = (math.cos(alpha), math.sin(alpha), 0.0)
        pts = []
        for k in range(361):
            t = math.radians(k)
            p = (math.sin(t) * a[0], math.sin(t) * a[1], math.cos(t))
            u, v = to_uv(p)
            pts.append((u * GW, v * GH))
        paths.append(pts)
    for v in (0.16, 0.84):
        paths.append([(GW * k / 64, GH * v) for k in range(65)])
    # 漩渦：從斜大圓上的點捲出去（1.6 圈、半徑遞減）。
    for i, (t_deg, side) in enumerate(((55, 1), (125, -1), (235, 1), (305, -1), (-40, -1), (40, 1))):
        alpha = math.radians(28) if i % 2 == 0 else math.radians(-62)
        t = math.radians(t_deg)
        u, v = to_uv((math.sin(t) * math.cos(alpha), math.sin(t) * math.sin(alpha), math.cos(t)))
        cx, cy = u * GW, v * GH
        pts = []
        for k in range(49):
            s = k / 48 * 1.6 * 2 * math.pi
            rad = 26 * (1 - k / 60)
            pts.append((cx + side * rad * (1 - math.cos(s)) * 0.9, cy + rad * math.sin(s)))
        paths.append(pts)
    return paths


def _clouds(rng: random.Random, w: int, h: int) -> Image.Image:
    grid = Image.new("L", (16, 10))
    grid.putdata([rng.randrange(256) for _ in range(160)])
    return grid.resize((w, h), Image.Resampling.BICUBIC)


def _sparkle(d: ImageDraw.ImageDraw, cx: float, cy: float, size: float, fill) -> None:
    """四芒星（1x 座標，畫在 SS 倍畫布）。"""
    s, w = size * SS, size * SS * 0.22
    x, y = cx * SS, cy * SS
    d.polygon([(x, y - s), (x + w, y - w), (x + s, y), (x + w, y + w), (x, y + s), (x - w, y + w),
               (x - s, y), (x - w, y - w)], fill=fill)


def _sparkle_spots(rng: random.Random, count: int, cage: Image.Image) -> list[tuple[float, float]]:
    """玻璃上不壓到黃銅框的光點位置（避開兩極）。"""
    spots = []
    while len(spots) < count:
        x, y = rng.uniform(0, GW), rng.uniform(GH * 0.25, GH * 0.75)
        if cage.getpixel((int(x * SS), int(y * SS))) == 0:
            spots.append((x, y))
    return spots


def draw_atlas(path: Path, emit_path: Path, colour: tuple[int, int, int], loaded: bool) -> Path:
    rng = random.Random(SEED)
    cloud = _clouds(rng, GW, GH)
    im = Image.new("RGB", (ATLAS, ATLAS), BRASS)
    px = im.load()
    cl = cloud.load()
    for y in range(GH):
        v = (y + 0.5) / GH
        eq = math.exp(-((v - 0.5) / 0.16) ** 2)
        for x in range(GW):
            k = 0.72 + 0.38 * cl[x, y] / 255
            c = [min(255, ch * k) for ch in colour]
            mix = (0.18 + 0.42 * eq) if loaded else 0.12 * eq
            px[x, y] = tuple(round(ch + (255 - ch) * mix) for ch in c)
    # 黃銅：尖頂沿輪廓明暗交替；飾片中心亮、外緣深（32 px 下才看得出尖角）。
    bx0, by0, bx1, by1 = RECTS["brass"]
    for y in range(by0, by1):
        t = (y - by0) / (by1 - by0)
        w = 0.5 + 0.5 * math.cos(t * 3 * math.pi)
        col = tuple(round(BRASS[i] * (1 - w) + BRASS_LIGHT[i] * w) for i in range(3))
        ImageDraw.Draw(im).line((bx0, y, bx1 - 1, y), fill=col)
    ox0, oy0, ox1, oy1 = RECTS["ornament"]
    for y in range(oy0, oy1):
        for x in range(ox0, ox1):
            r = math.hypot((x - (ox0 + ox1) / 2) / ((ox1 - ox0) / 2), (y - (oy0 + oy1) / 2) / ((oy1 - oy0) / 2))
            w = max(0.0, 1 - r)
            edge = BRASS_DARK if w < 0.5 else BRASS
            t = w * 2 if w < 0.5 else (w - 0.5) * 2
            hi_col = BRASS if w < 0.5 else BRASS_LIGHT
            px[x, y] = tuple(round(edge[i] * (1 - t) + hi_col[i] * t) for i in range(3))

    hi = im.resize((ATLAS * SS, ATLAS * SS), Image.Resampling.NEAREST)
    d = ImageDraw.Draw(hi)
    # 玻璃內的細亮紋（裂冰感）。
    for _ in range(14):
        x, y = rng.uniform(0, GW), rng.uniform(GH * 0.15, GH * 0.85)
        pts = [(x, y)]
        for _ in range(6):
            x, y = x + rng.uniform(-18, 18), y + rng.uniform(-10, 10)
            pts.append((x, y))
        tint = tuple(round(ch + (255 - ch) * 0.45) for ch in colour)
        _polyline(d, pts, tint, 1)
    cage = Image.new("L", hi.size, 0)
    cd = ImageDraw.Draw(cage)
    paths = _cage()
    for pts in paths:
        _polyline(d, pts, BRASS_DARK, BAND_W + 3)
        _polyline(cd, pts, 255, BAND_W + 3)
    for pts in paths:
        _polyline(d, pts, BRASS, BAND_W)
    for pts in paths:
        _polyline(d, pts, BRASS_LIGHT, 2)
    if loaded:
        for x, y in _sparkle_spots(rng, 22, cage):
            _sparkle(d, x, y, rng.uniform(5, 9), (255, 255, 255))
    hi.resize((ATLAS, ATLAS), Image.Resampling.LANCZOS).save(path, format="PNG")
    _emit_atlas(colour, loaded, cage).save(emit_path, format="PNG")
    return emit_path


def _emit_atlas(colour, loaded: bool, cage: Image.Image) -> Image.Image:
    """圖示用的無光照疊層（lighter 疊回 Workbench 算圖），黃銅框處全黑（不蓋框）。
    空的：朝圖示相機的球心發出本色光（發光玻璃）；裝了：同樣的本色光，正中再一團近白的熱點＋三顆大光點。"""
    a, e = math.radians(ICON_VIEW["az"]), math.radians(ICON_VIEW["el"])
    view = (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))
    em = Image.new("RGB", (ATLAS, ATLAS), (0, 0, 0))
    px = em.load()
    for y in range(GH):
        for x in range(GW):
            p = direction((x + 0.5) / GW, (y + 0.5) / GH)
            g = max(0.0, sum(i * j for i, j in zip(p, view)))
            hot = 0.95 * g ** 4 if loaded else 0.0
            px[x, y] = tuple(round(ch * g ** 1.5 * (1 - hot) + 255 * hot) for ch in colour)
    hi = em.resize((ATLAS * SS, ATLAS * SS), Image.Resampling.BICUBIC)
    d = ImageDraw.Draw(hi)
    if loaded:  # 大光點放在相機看得到的那一面，偏離球心一點。
        u, v = to_uv(view)
        for du, dv, size in ((0.12, -0.08, 22), (-0.10, 0.12, 16), (0.02, 0.16, 12)):
            _sparkle(d, ((u + du) % 1) * GW, (v + dv) * GH, size, (255, 255, 255))
    hi.paste((0, 0, 0), (0, 0), cage)
    return hi.resize((ATLAS, ATLAS), Image.Resampling.LANCZOS)


def run_blender(blender: Path, atlases: list[tuple[Path, Path]], out: Path) -> None:
    cfg = WORK / "config.json"
    cfg.write_text(json.dumps({
        "here": str(HERE), "media": str(MEDIA), "out": str(out), "tex": ATLAS, "rects": RECTS,
        "icon_view": ICON_VIEW,
        "atlases": [{"path": str(p), "emit": str(e)} for p, e in atlases],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    cmd = [str(blender), "-b", "--factory-startup", "--python", str(BLENDER_SCRIPT), "--", str(cfg)]
    proc = subprocess.run(cmd, cwd=str(REPO), capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode != 0 or "BUILD OK" not in proc.stdout:
        print(proc.stdout[-12000:])
        print(proc.stderr[-12000:], file=sys.stderr)
        raise RuntimeError(f"Blender 產線失敗（exit {proc.returncode}）")


def make_sheet(icons: list[Path], out: Path) -> None:
    """四欄（Tier）× 空／裝了：圖示 1x、4x、EEVEE 世界模型；左上附膠囊圖示 1x 對照大小。"""
    bg, ink = (45, 46, 49, 255), (225, 225, 225, 255)
    font = ImageFont.truetype(str(FONT_BOLD), 18)
    col = 300
    sheet = Image.new("RGBA", (24 + col * len(TIERS), 40 + 48 + 140 + 2 * 200 + 30), bg)
    d = ImageDraw.Draw(sheet)
    capsule = MEDIA / "textures/Item_MinidoracatCapsuleCartoon.png"
    for c, (tier, _) in enumerate(TIERS):
        x = 24 + c * col
        d.text((x, 10), tier, font=font, fill=ink)
        pair = [Image.open(p).convert("RGBA") for p in icons[c * 2:c * 2 + 2]]
        for k, im in enumerate(pair):
            sheet.alpha_composite(im, (x + k * 44, 44))
            sheet.alpha_composite(im.resize((128, 128), Image.Resampling.NEAREST), (x + k * 140, 88))
            model = Image.open(out / f"model_{icons[c * 2 + k].stem[5:]}.png").convert("RGBA")
            model = model.resize((260, 195), Image.Resampling.LANCZOS)
            sheet.alpha_composite(model, (x, 236 + k * 200))
        if c == 0 and capsule.is_file():
            sheet.alpha_composite(Image.open(capsule).convert("RGBA"), (x + 100, 44))
    d.text((24, sheet.height - 26), "cols: empty / loaded (1x row: + capsule for size)  rows: 1x, 4x, model empty, model loaded",
           font=font, fill=ink)
    sheet.save(WORK / "sheet.png", format="PNG")


def run(args: argparse.Namespace) -> None:
    blender = Path(args.blender).resolve()
    if not blender.is_file():
        raise FileNotFoundError(f"找不到 Blender：{blender}")
    texture_dir = MEDIA / "textures/WorldItems"
    texture_dir.mkdir(parents=True, exist_ok=True)
    out = WORK / "blender-out"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    atlases = []
    for tier, colour in TIERS:
        for loaded in (False, True):
            path = texture_dir / f"MinidoracatSphere{tier}{'Loaded' if loaded else ''}.png"
            atlases.append((path, draw_atlas(path, out / f"emit_{path.stem}.png", colour, loaded)))
    run_blender(blender, atlases, out)

    icons = []
    for atlas, _ in atlases:
        src = out / f"icon_{atlas.stem}.png"
        _check_png(src, (256, 256))
        lit = Image.open(src).convert("RGBA")
        merged = ImageChops.lighter(lit.convert("RGB"), Image.open(out / f"icon_{atlas.stem}_emit.png").convert("RGB"))
        merged.putalpha(lit.getchannel("A"))
        merged.save(src, format="PNG")
        icons.append(dst := MEDIA / f"textures/Item_{atlas.stem}.png")
        icon(src, dst)
    make_sheet(icons, out)
    shutil.copyfile(out / "fbx_verify.txt", WORK / "fbx_verify.txt")

    for p, _ in atlases:
        _check_png(p, (ATLAS, ATLAS), "RGB")
    for p in icons:
        _check_png(p, (32, 32), "RGBA")
    fbx = MEDIA / "models_X/WorldItems/MinidoracatSphere.fbx"
    if not fbx.is_file() or fbx.stat().st_size == 0:
        raise AssertionError(f"缺少 FBX：{fbx}")
    print("BUILD OK ->", MEDIA)
    print("sheet ->", WORK / "sheet.png")


def main() -> None:
    ap = argparse.ArgumentParser(description="建立帕魯球的 atlas、FBX、PZ 物品圖示與預覽")
    ap.add_argument("--blender", default=str(BLENDER_DEFAULT), help="Blender 5.2 可執行檔絕對路徑")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
