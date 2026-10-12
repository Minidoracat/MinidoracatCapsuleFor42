# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "numpy"]
# ///
"""卡通煙霧 8 幀：把 codex imagegen 生成的 4x2 sprite sheet（品紅 #FF00FF 底）切開、去背，寫成 MOD 用的 256x256 PNG。

用法（repo 根目錄）：
    uv run scripts/assets/build_smoke.py
來源：scripts/assets/smoke_sheet.png（1536x1024，每格 384x512；提示詞 scripts/assets/prompts/codex-smoke-sheet.txt）。
產物：media/textures/MinidoracatCapsule/smoke_1.png … smoke_8.png（RGBA，透明底）。

去背：煙只有白到灰（R≈G≈B），底是品紅（R=B=255、G=0）。把像素看成 a·煙 + (1-a)·品紅，
G 不受品紅影響，所以 1-a ≈ ((R+B)/2 - G) / 255；再用 a 反解出煙本身的顏色（去掉品紅溢色）。
所有幀用同一個錨點（格子水平中心＋各幀內容垂直中心的中位數）與同一個縮放，膨脹與散開的大小變化原樣保留。
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, "smoke_sheet.png")
OUT = os.path.join(REPO, "MOD", "MinidoracatCapsuleFor42", "Contents", "mods", "MinidoracatCapsuleFor42",
                   "42", "media", "textures", "MinidoracatCapsule")
COLS, ROWS, SIZE = 4, 2, 256
KEY = np.array([255.0, 0.0, 255.0])


def unkey(rgb):
    """rgb float (h, w, 3) 0..255 → RGBA uint8，品紅底變透明、邊緣去溢色。"""
    spill = ((rgb[..., 0] + rgb[..., 2]) / 2 - rgb[..., 1]) / 255.0
    a = np.clip(1.0 - spill, 0.0, 1.0)
    a[a < 0.08] = 0.0          # 底色上的壓縮雜訊
    a[a > 0.94] = 1.0
    safe = np.maximum(a, 1e-3)[..., None]
    fg = np.clip((rgb - (1.0 - a[..., None]) * KEY) / safe, 0, 255)
    fg[a == 0] = 0
    return np.dstack([fg, a * 255]).round().astype(np.uint8)


def main():
    sheet = np.asarray(Image.open(SRC).convert("RGB"), dtype=np.float64)
    h, w, _ = sheet.shape
    cw, ch = w // COLS, h // ROWS
    cells = [unkey(sheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]) for r in range(ROWS) for c in range(COLS)]
    boxes = []
    for i, cell in enumerate(cells, 1):
        ys, xs = np.nonzero(cell[..., 3] > 0)
        if not len(xs):
            raise SystemExit(f"第 {i} 格沒有內容")
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        if min(x0, y0) < 4 or x1 > cw - 5 or y1 > ch - 5:
            raise SystemExit(f"第 {i} 格的煙碰到格子邊（{x0},{y0}-{x1},{y1}），重生 sheet")
        boxes.append((x0, y0, x1, y1))
    cx = cw / 2
    cy = float(np.median([(b[1] + b[3]) / 2 for b in boxes]))
    half = max(max(abs(b[0] - cx), abs(b[2] - cx), abs(b[1] - cy), abs(b[3] - cy)) for b in boxes) + 6
    os.makedirs(OUT, exist_ok=True)
    for i, cell in enumerate(cells, 1):
        im = Image.fromarray(cell, "RGBA")
        # 預乘 alpha 再縮，透明處的黑色不會滲進邊緣
        crop = im.crop((round(cx - half), round(cy - half), round(cx + half), round(cy + half)))
        frame = crop.convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
        frame.save(os.path.join(OUT, f"smoke_{i}.png"), optimize=True)
        b = boxes[i - 1]
        print(f"smoke_{i}.png  content {b[2] - b[0] + 1}x{b[3] - b[1] + 1} px in cell -> "
              f"{(b[2] - b[0] + 1) * SIZE / (2 * half):.0f} px in {SIZE}")
    print(f"crop {2 * half:.0f} px square per cell, anchor ({cx:.0f},{cy:.0f}) -> {os.path.relpath(OUT, REPO)}")


if __name__ == "__main__":
    main()
