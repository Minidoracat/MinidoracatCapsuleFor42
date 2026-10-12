# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""萬用膠囊七種款式的音效挑選頁：卡通以外六款 × 四段（丟出、彈開、收車、按鈕），每段 4 個 ElevenLabs 候選，
每款配一個遊戲畫面，按 ▶ 就照遊戲的時間軸播那一段的特效（2026-10-12 使用者要求「加上對應的特效動畫搭配組合」）。

2026-10-12 使用者在設計稿 vcap-types-1012 選「28 段全部由你挑」，補一句「卡通的音效就先維持吧」：卡通四段只當參考。
候選：第 5 版提示詞 scripts/assets/sfx_v5.json（temp/assets-review/sfx-v5/raw），以及原本借用別款的 5 段新提示詞
scripts/assets/sfx_v6.json（sfx-v6/raw）。每條照 build_sfx.write 的整理（design_fx.py 同一條柔化規則、level_af、彈開
-14 dBFS）後轉 MP3 內嵌，聽到的就是裝進 MOD 的樣子。「目前」是 build_sfx.SPEC 現在選的那條。
畫面：E2E fxbg-sp 的遊戲截圖（正午、晴天、預設縮放，--bg），裁切與時間軸照 design_fx.py（Effects.lua 的畫法）；
按鈕與收車畫面地上那顆膠囊，每款用自己那張截圖裁下的一小塊蓋上去。煙霧幀、飛行圖示、款式參數取 MOD 本身
（media/textures、Core.lua M.TYPES）。

    uv run scripts/assets/pick_sfx.py [--bg temp/e2e-vcap-fxbg-<id>]   # 寫 temp/assets-review/sfx-pick/vcap-sfx-pick-<MMDD>.html
    orca artifacts share <那個檔> --json   # 改版後對同一路徑 orca artifacts update，連結不變
選定後把 build_sfx.SPEC 改成 "v5:<ID>_<n>" 或 "v6:<ID>_<n>"，再 `uv run scripts/assets/build_sfx.py --write <名稱>`。
"""
import argparse
import base64
import datetime
import html
import io
import json
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_sfx as bs  # noqa: E402
import design_fx as fx  # noqa: E402  (timeline constants and the background crop shared with the effect demo page)

OUT = os.path.join(bs.REVIEW, "sfx-pick")
SOUNDS = bs.OUT
CORE = os.path.join(fx.MOD_MEDIA, "lua", "shared", "MinidoracatCapsule", "Core.lua")
TEX = os.path.join(fx.MOD_MEDIA, "textures")
SOFT_ABOVE_HZ = 4000  # design_fx.py 同一條：頻譜重心超過、而且提示詞是容易刺耳的音色才柔化
SHRILL = re.compile(r"shimmer|sparkl|twinkl|chime|blip|zap|whir|electric", re.I)
SCALE = 0.75  # stage canvas 960x540 = the 1280x720 crop at zoom 1
W, H = round(fx.CROP_W * SCALE), round(fx.CROP_H * SCALE)
JPEG_Q = 82
TYPE_RE = re.compile(r'\{ id = "(\w+)", smoke = "(\w+)", frames = (\d+), frameMs = (\d+), px = (\d+), anchor = ([\d.]+)')

NAMES = {  # id -> 中文, 效果說明（Tooltip Look_<id> 的繁中）
    "Cartoon": ("卡通", "白色卡通煙霧，卡通音效"),
    "Real": ("寫實", "灰色煙霧，機械與氣壓聲"),
    "Dust": ("塵土", "塵土貼地炸開，重物落地聲"),
    "Steam": ("蒸汽", "白色蒸氣，蒸汽噴發聲"),
    "SciFi": ("科幻", "光柱與地面光環，能量聲"),
    "Magic": ("魔法", "淡紫色煙霧與星芒，魔法聲"),
    "Shock": ("衝擊", "蘑菇雲與地面衝擊波，爆炸聲"),
}
ACTIONS = [("Throw", "丟出"), ("Pop", "彈開"), ("Pack", "收車"), ("Button", "按鈕")]
RANGE = {"Throw": bs.THROW, "Pop": bs.POP, "Pack": bs.PACK, "Button": bs.BUTTON}
# (款式, 段) -> (MOD 音效名, 候選版本, 提示詞 id；一列放幾句提示詞時是 tuple，每句 4 條，依序編號)
SLOTS = {
    ("Real", "Throw"): ("UniversalCapsuleThrowReal", "v5", "ThrowReal"),
    ("Real", "Pop"): ("UniversalCapsulePopReal", "v5", "PopReal"),
    ("Real", "Pack"): ("UniversalCapsulePackReal", "v5", "PackReal"),
    ("Real", "Button"): ("UniversalCapsuleButtonReal", "v5", "ButtonReal"),
    ("Dust", "Throw"): ("UniversalCapsuleThrowReal2", "v5", "ThrowReal2"),
    ("Dust", "Pop"): ("UniversalCapsulePopHeavyDrop", "v5", "PopHeavyDrop"),
    ("Dust", "Pack"): ("UniversalCapsulePackHeavy", "v5", "PackHeavy"),
    ("Dust", "Button"): ("UniversalCapsuleButtonDust", "v6", "ButtonDust"),
    ("Steam", "Throw"): ("UniversalCapsuleThrowSteam", "v6", "ThrowSteam"),
    ("Steam", "Pop"): ("UniversalCapsulePopSteam", "v5", "PopSteam"),
    ("Steam", "Pack"): ("UniversalCapsulePackSteam", "v5", "PackSteam"),
    ("Steam", "Button"): ("UniversalCapsuleButtonSwitch", "v5", "ButtonSwitch"),
    ("SciFi", "Throw"): ("UniversalCapsuleThrowSci", "v5", "ThrowSci"),
    ("SciFi", "Pop"): ("UniversalCapsulePopSci", "v5", "PopSci"),
    ("SciFi", "Pack"): ("UniversalCapsulePackSci", "v5", "PackSci"),
    ("SciFi", "Button"): ("UniversalCapsuleButtonSci", "v5", "ButtonSci"),
    ("Magic", "Throw"): ("UniversalCapsuleThrowMagic", "v5", "ThrowMagic"),
    ("Magic", "Pop"): ("UniversalCapsulePopMagic", "v5", "PopMagic"),
    ("Magic", "Pack"): ("UniversalCapsulePackMagic", "v5", "PackMagic"),
    ("Magic", "Button"): ("UniversalCapsuleButtonMagic", "v5", "ButtonMagic"),
    ("Shock", "Throw"): ("UniversalCapsuleThrowShock", "v6", "ThrowShock"),
    ("Shock", "Pop"): ("UniversalCapsulePopExplosion", "v7", ("PopBoom", "PopBlast", "PopMushroom")),
    ("Shock", "Pack"): ("UniversalCapsulePackShock", "v6", "PackShock"),
    ("Shock", "Button"): ("UniversalCapsuleButtonShock", "v6", "ButtonShock"),
}
GROUP = {"PopBoom": "厚重轟隆", "PopBlast": "電影感爆破", "PopMushroom": "蘑菇雲火球"}  # 多句提示詞那一列的分組標題
# stage scene -> (before shot, after shot); the capsule lies on the ground in press "before" (at C) and pack "after" (at T)
SCENES = (("throw", "throw-empty", "throw-car"), ("press", "press-capsule", "press-car"), ("pack", "pack-car", "pack-empty"))
PATCHED = {"press": ("before", "csx", "csy"), "pack": ("after", "tsx", "tsy")}
PATCH_WIN = 64   # canvas px around the capsule where the type shots may differ from the cartoon one
PATCH_DIFF = 40  # summed RGB difference that counts as changed
MCU = 16         # patch box on the JPEG block grid: unchanged blocks decode the same as the background


def mp3(args, data=None):
    """ffmpeg → MP3 96 kbps 單聲道（手機瀏覽器都能播）的 bytes。"""
    return subprocess.run(["ffmpeg", "-v", "error", *args, "-ac", "1", "-ar", str(bs.SR), "-c:a", "libmp3lame",
                           "-b:a", "96k", "-map_metadata", "-1", "-f", "mp3", "pipe:1"],
                          input=data, capture_output=True, check=True).stdout


def candidate(name, take, text, seg):
    """整理一條候選（build_sfx.load：含 CUT 剪掉的開頭），回傳 (MP3 bytes, 有聲長度, 註記)。"""
    a = bs.load(name, take)
    if bs.stats(a)["centroid"] > SOFT_ABOVE_HZ and SHRILL.search(text):
        a = bs.soften(a)
    s = bs.stats(a)
    data = mp3(["-f", "f32le", "-ar", str(bs.SR), "-ac", "1", "-i", "pipe:0", "-af", bs.level_af(s, bs.target_db(name))],
               a.astype("<f4").tobytes())
    lo, hi = RANGE[seg]
    note = "" if lo <= s["active"] <= hi else ("太短" if s["active"] < lo else "太長")
    return data, s["active"], note


def data_uri(b, mime):
    return f"data:{mime};base64," + base64.b64encode(b).decode("ascii")


def png_bytes(im):
    b = io.BytesIO()
    im.save(b, "PNG", optimize=True)
    return b.getvalue()


def core_types():
    """Core.lua M.TYPES in order: id, smoke prefix, frames, frameMs, px, anchor."""
    src = open(CORE, encoding="utf-8").read()
    types = [{"id": m[1], "smoke": m[2], "frames": int(m[3]), "frameMs": int(m[4]), "px": int(m[5]),
              "anchor": float(m[6])} for m in TYPE_RE.finditer(src)]
    if [t["id"] for t in types] != list(NAMES):
        sys.exit(f"Core.lua M.TYPES {[t['id'] for t in types]} != {list(NAMES)}")
    return types


def smoke_frames(t):
    """The type's smoke frames as WebP data URIs (lossy q80 with alpha: 7.5 MB of PNG -> ~1.3 MB)."""
    out = []
    for i in range(1, t["frames"] + 1):
        b = io.BytesIO()
        Image.open(os.path.join(TEX, "MinidoracatCapsule", f"{t['smoke']}{i}.png")).convert("RGBA").save(
            b, "WEBP", quality=80, method=4)
        out.append(data_uri(b.getvalue(), "image/webp"))
    return out


def stages(bg, type_ids):
    """fxbg-sp shots -> per scene the before/after background (JPEG, canvas size) and the screen points of the player
    and the landing point; per patched scene a small PNG per type covering the capsule on the ground."""
    log = open(os.path.join(bg, "client1", "console.txt"), encoding="utf-8", errors="replace").read()
    coords = {m.group(1): {k: float(v) for k, v in re.findall(r"(\w+)=([-\d.]+)", m.group(2))}
              for m in fx.COORD.finditer(log)}
    shots = os.path.join(bg, "client1", "Screenshots")
    scenes, patches = {}, {}
    for key, before, after in SCENES:
        c = coords[before]
        z = c["zoom"]
        x0 = int(round(min(max(c["tsx"] - fx.CROP_W / 2, 0), c["sw"] - fx.CROP_W)))
        y0 = int(round(min(max(c["tsy"] - fx.CROP_UP / z, 0), c["sh"] - fx.CROP_H)))
        box = (x0, y0, x0 + fx.CROP_W, y0 + fx.CROP_H)

        def shot(tag):
            im = Image.open(os.path.join(shots, f"fxbg-{tag}.png")).convert("RGB").crop(box).resize((W, H), Image.LANCZOS)
            b = io.BytesIO()
            im.save(b, "JPEG", quality=JPEG_Q, optimize=True)
            jpg = b.getvalue()
            return jpg, np.asarray(Image.open(io.BytesIO(jpg)).convert("RGB"), dtype=np.int16)

        def pt(name):
            return round((c[name] - (x0 if name.endswith("x") else y0)) * SCALE, 1)

        jb, ab = shot(before)
        ja, aa = shot(after)
        scenes[key] = {"before": data_uri(jb, "image/jpeg"), "after": data_uri(ja, "image/jpeg"), "zoom": z,
                       "tsx": pt("tsx"), "tsy": pt("tsy"), "psx": pt("psx"), "psy": pt("psy")}
        if key not in PATCHED:
            continue
        side, kx, ky = PATCHED[key]
        base = ab if side == "before" else aa
        tag = before if side == "before" else after
        cx, cy = pt(kx), pt(ky) + 16 * SCALE / z  # the capsule lies on the tile centre: half a tile below its corner
        typed = {tid: shot(f"{tag}-{tid}")[1] for tid in type_ids[1:]}
        mask = np.zeros(base.shape[:2], bool)
        for arr in typed.values():
            mask |= np.abs(arr - base).sum(axis=2) > PATCH_DIFF
        win = np.zeros_like(mask)
        win[max(0, int(cy - PATCH_WIN)):int(cy + PATCH_WIN), max(0, int(cx - PATCH_WIN)):int(cx + PATCH_WIN)] = True
        ys, xs = np.nonzero(mask & win)
        if len(xs) == 0:
            sys.exit(f"{key}: the type shots show no capsule difference near ({cx}, {cy})")
        px0, py0 = max(0, (xs.min() - MCU) // MCU * MCU), max(0, (ys.min() - MCU) // MCU * MCU)
        px1, py1 = min(W, -(-(xs.max() + MCU) // MCU) * MCU), min(H, -(-(ys.max() + MCU) // MCU) * MCU)
        patches[key] = {"side": side, "x": int(px0), "y": int(py0), "img": {
            tid: data_uri(png_bytes(Image.fromarray(arr[py0:py1, px0:px1].astype(np.uint8))), "image/png")
            for tid, arr in typed.items()}}
        print(f"patch {key}: {px1 - px0}x{py1 - py0} at ({px0},{py0}), capsule ({cx:.0f},{cy:.0f})")
    return scenes, patches


def build(bg):
    types = core_types()
    type_ids = [t["id"] for t in types]
    scenes, patches = stages(bg, type_ids)
    look = {}
    for t in types:
        sprite = open(os.path.join(TEX, f"Item_MinidoracatCapsule{t['id']}Loaded.png"), "rb").read()
        look[t["id"]] = {"frames": smoke_frames(t), "frameMs": t["frameMs"], "px": t["px"], "anchor": t["anchor"],
                         "sprite": data_uri(sprite, "image/png")}
    prompts = {}
    for v in ("v5", "v6", "v7"):
        for it in json.load(open(os.path.join(HERE, f"sfx_{v}.json"), encoding="utf-8")):
            prompts[(v, it["id"])] = it["text"]
    snd, rows_js, cur = {}, [], {}
    for seg, _ in ACTIONS:
        snd[f"Cartoon_{seg}"] = data_uri(mp3(["-i", os.path.join(SOUNDS, f"UniversalCapsule{seg}.ogg")]), "audio/mpeg")
    sections = []
    for tid in type_ids:
        tname, desc = NAMES[tid]
        rows = []
        if tid != "Cartoon":
            for seg, label in ACTIONS:
                name, ver, pids = SLOTS[(tid, seg)]
                pids = (pids,) if isinstance(pids, str) else pids
                takes = [f"{ver}:{p}_{k}" for p in pids for k in range(1, 5)]
                spec = str(bs.SPEC.get(name, (None, ""))[1] or "")
                if spec not in takes:
                    sys.exit(f"build_sfx.SPEC {name} = {spec!r}: not one of this row's takes")
                cur_n = takes.index(spec) + 1
                slot = f"{tid}.{seg}"
                chips = []
                for n, take in enumerate(takes, 1):
                    pid = take.split(":")[1].rsplit("_", 1)[0]
                    if len(pids) > 1 and take.endswith("_1"):
                        chips.append(f'<span class="grp">{GROUP[pid]}（{n}–{n + 3}）</span>')
                    data, active, note = candidate(name, take, prompts[(ver, pid)], seg)
                    key = f"{tid}_{seg}_{n}"
                    snd[key] = data_uri(data, "audio/mpeg")
                    tag = '<span class="cur">目前</span>' if n == cur_n else ""
                    warn = f'<span class="warn">{note}</span>' if note else ""
                    checked = " checked" if n == cur_n else ""
                    chips.append(
                        f'<label class="chip"><input type="radio" name="{slot}" value="{n}"{checked}>'
                        f'<button type="button" class="play" data-t="{tid}" data-seg="{seg}" data-n="{n}" '
                        f'aria-label="播放 {tname} {label} 候選 {n}，連同特效">▶ {n}</button>'
                        f'<span class="len">{active:.1f}s</span>{warn}{tag}</label>')
                    print(f"{slot:14s} {n}  {active:.2f}s {note}")
                chips.append(f'<label class="chip redo"><input type="radio" name="{slot}" value="redo">都不喜歡</label>')
                rows.append(f'<div class="row"><div class="seg">{label}</div><div class="chips">{"".join(chips)}</div></div>')
                rows_js.append({"slot": slot, "label": f"{tname}・{label}"})
                cur[slot] = cur_n
        icon = f'<img src="{look[tid]["sprite"]}" width="32" height="32" alt="">'
        note = "維持現在的四段，只當參考" if tid == "Cartoon" else html.escape(desc)
        scene_btns = "".join(
            f'<button type="button" class="scene" data-t="{tid}" data-scene="{k}" aria-label="{tname}：{lab}">▶ {lab}</button>'
            for k, lab in (("throw", "丟出→彈開"), ("press", "按鈕→彈開"), ("pack", "收車")))
        combo = "卡通四段" if tid == "Cartoon" else "用現在勾的組合"
        sections.append(
            f'<section id="t-{tid}"><h2>{icon}{tname}<small>{note}</small></h2>'
            f'<canvas class="stage" data-t="{tid}" width="{W}" height="{H}" role="img" aria-label="{tname}膠囊的特效畫面"></canvas>'
            f'<p class="cap" aria-live="polite" data-t="{tid}">按下面的 ▶ 播放</p>'
            f'<div class="scenes"><span>{combo}整段試播：</span>{scene_btns}</div>{"".join(rows)}</section>')
    cfg = {"w": W, "h": H, "scale": SCALE, "lead": fx.LEAD_MS, "flight": fx.FLIGHT_MS, "press": fx.PRESS_MS,
           "arc": fx.ARC_PX, "capsulePx": fx.CAPSULE_PX, "scenes": scenes, "patches": patches, "look": look,
           "snd": snd, "rows": rows_js, "cur": cur}
    return cfg, sections


PAGE = """<!doctype html>
<html lang="zh-Hant-TW"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>萬用膠囊音效挑選</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; font: 15px/1.5 "Microsoft JhengHei", "Noto Sans TC", "PingFang TC", system-ui, sans-serif; background: #17181b; color: #ececec; }
  main { max-width: 760px; margin: 0 auto; padding: 16px 14px 48px; }
  h1 { font-size: 20px; margin: 0 0 6px; }
  .intro { color: #c4c4c4; font-size: 14px; margin: 0 0 10px; padding-inline-start: 20px; }
  .intro li { margin: 2px 0; }
  .opt { display: flex; align-items: center; gap: 8px; min-height: 44px; font-size: 14px; color: #ececec; }
  .opt input { width: 18px; height: 18px; margin: 0; accent-color: #ffd966; }
  section { background: #222429; border: 1px solid #34363c; border-radius: 10px; padding: 10px 12px; margin: 12px 0; }
  h2 { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; font-size: 17px; margin: 0 0 8px; }
  h2 img { image-rendering: pixelated; }
  h2 small { font-size: 13px; font-weight: 400; color: #b8b8b8; }
  .stage { display: block; width: 100%; height: auto; aspect-ratio: 16 / 9; border-radius: 8px; background: #000; }
  .cap { min-height: 21px; margin: 6px 0 4px; font-size: 13px; color: #c4c4c4; }
  .scenes { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; padding: 4px 0 8px; font-size: 13px; color: #b8b8b8; }
  .scene { min-height: 40px; padding: 0 12px; border: 1px solid #6a6d75; border-radius: 6px; background: #2f3138; color: #fff; font-size: 14px; }
  .row { display: grid; grid-template-columns: 52px 1fr; gap: 8px; align-items: center; padding: 6px 0; border-top: 1px solid #30323a; }
  .seg { font-weight: 600; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { display: inline-flex; align-items: center; gap: 6px; min-height: 44px; padding: 0 8px; border: 1px solid #4a4d55; border-radius: 8px; background: #1b1c20; }
  .chip:has(input:checked) { border-color: #ffd966; background: #2c2a1c; }
  .chip input { width: 18px; height: 18px; margin: 0; accent-color: #ffd966; }
  .play { min-width: 52px; min-height: 36px; border: 1px solid #6a6d75; border-radius: 6px; background: #2f3138; color: #fff; font-size: 14px; }
  .play.on, .scene.on { background: #ffd966; color: #1a1405; border-color: #ffd966; }
  .len { font-size: 12px; color: #b8b8b8; font-variant-numeric: tabular-nums; }
  .warn { font-size: 12px; color: #ffb38a; }
  .cur { font-size: 11px; padding: 0 5px; border: 1px solid #9fd39d; color: #9fd39d; border-radius: 8px; }
  .redo { color: #d0d0d0; font-size: 14px; }
  .grp { flex-basis: 100%; font-size: 12px; color: #b8b8b8; margin-top: 2px; }
  .out { position: sticky; bottom: 0; background: #17181b; padding: 10px 0 4px; border-top: 1px solid #34363c; }
  textarea { width: 100%; box-sizing: border-box; height: 76px; background: #0f1012; color: #ececec; border: 1px solid #4a4d55; border-radius: 8px; font: 13px/1.5 ui-monospace, Consolas, monospace; padding: 8px; }
  .bar { display: flex; gap: 10px; align-items: center; margin-top: 6px; }
  .copy { min-height: 44px; padding: 0 16px; border: 0; border-radius: 8px; background: #ffd966; color: #1a1405; font-weight: 700; font-size: 15px; }
  .sum { color: #c4c4c4; font-size: 14px; }
</style>
<body><main>
<h1>萬用膠囊音效挑選：六款 × 四段，配特效</h1>
<ul class="intro">
  <li>按 ▶ 試聽，畫面會照遊戲的時間軸播那一段特效：丟出、彈開用「丟出」畫面（膠囊飛 0.5 秒落地彈開），按鈕用「按下按鈕」畫面（按下 0.8 秒後出車），收車用「收車」畫面。</li>
  <li>同一個畫面裡的另一段聲音，用那一列現在勾的那條。每款畫面下的三顆按鈕，用現在勾的組合整段播一次。</li>
  <li>背景是遊戲內截圖（正午、預設縮放），煙霧和飛行中的膠囊照遊戲的畫法與大小。遊戲裡的閃光白天看不出來，這裡不畫；遊戲裡的聲音還會隨距離變小。</li>
  <li>數字後面是有聲長度；丟出最好在 0.9 秒內。每列預先勾好 MOD 現在用的那條（標「目前」）。「都不喜歡」：那一列我重寫提示詞再生成一批。</li>
  <li>衝擊・彈開換成 12 個新的爆炸聲，分三種：厚重轟隆、電影感爆破、蘑菇雲火球；「目前」那條是我暫選的。</li>
  <li>選完按最下面「複製結果」貼回對話。<b>重新整理會清掉選擇</b>，請當場複製。iPhone 沒聲音時請關掉靜音模式。</li>
</ul>
<label class="opt"><input type="checkbox" id="solo"> 只播被點的那一段聲音（另一段只有畫面）</label>
__SECTIONS__
<div class="out">
  <textarea id="out" readonly aria-label="挑選結果"></textarea>
  <div class="bar"><button type="button" class="copy" id="copy">複製結果</button><span class="sum" id="sum"></span></div>
</div>
</main>
<script>const CFG = __CFG__;</script>
<script>
"use strict";
const $ = id => document.getElementById(id);
const SEG_SCENE = { Throw: "throw", Pop: "throw", Pack: "pack", Button: "press" };
const SEG_NAME = { Throw: "丟出", Pop: "彈開", Pack: "收車", Button: "按鈕" };
const IMG = {}, BUF = {}, STAGE = {};
let AC = null, run = null, token = 0, sources = [];

function img(src) {
  if (!IMG[src]) { const i = new Image(); i.src = src; IMG[src] = i; }
  return IMG[src];
}
const ready = srcs => Promise.all(srcs.map(s => img(s).decode().catch(() => {})));
function audio() {
  if (!AC) {
    if (navigator.audioSession) { try { navigator.audioSession.type = "playback"; } catch (e) {} }
    AC = new (window.AudioContext || window.webkitAudioContext)();
  }
  if (AC.state !== "running") AC.resume();
  return AC;
}
function buffer(key) {
  if (!BUF[key]) {
    const b64 = CFG.snd[key].split(",")[1];
    const bytes = Uint8Array.from(atob(b64), ch => ch.charCodeAt(0));
    BUF[key] = AC.decodeAudioData(bytes.buffer);
  }
  return BUF[key];
}
// every row starts on the current pick and a radio cannot be unchecked: a value is always there
const chosen = slot => document.querySelector(`input[name="${slot}"]:checked`).value;
// the sound key a slot plays with: the chosen candidate, or the current one when the row says redo
function pick(tid, seg) {
  if (tid === "Cartoon") return `Cartoon_${seg}`;
  const v = chosen(`${tid}.${seg}`);
  return `${tid}_${seg}_${v === "redo" ? CFG.cur[`${tid}.${seg}`] : v}`;
}
function plan(tid, scene) {
  const L = CFG.lead, lk = CFG.look[tid], smoke = lk.frames.length * lk.frameMs;
  if (scene === "throw") return { fx: L + CFG.flight, total: L + CFG.flight + smoke + 400, ev: [["Throw", L], ["Pop", L + CFG.flight]] };
  if (scene === "press") return { fx: L + CFG.press, total: L + CFG.press + smoke + 400, ev: [["Button", L], ["Pop", L + CFG.press]] };
  return { fx: L, total: L + smoke + 500, ev: [["Pack", L]] };
}
function sceneImages(tid, scene) {
  const sc = CFG.scenes[scene], pa = CFG.patches[scene];
  return [sc.before, sc.after, ...(pa && pa.img[tid] ? [pa.img[tid]] : [])];
}
// Effects.lua drawFlight / drawSmoke on the canvas: screen px at zoom 1 times CFG.scale
function draw(tid, scene, t) {
  const g = STAGE[tid].getContext("2d"), sc = CFG.scenes[scene], lk = CFG.look[tid], pa = CFG.patches[scene];
  const p = plan(tid, scene), after = t >= p.fx, k = CFG.scale / sc.zoom;
  g.drawImage(img(after ? sc.after : sc.before), 0, 0);
  if (pa && pa.img[tid] && (pa.side === "after") === after) g.drawImage(img(pa.img[tid]), pa.x, pa.y);
  if (scene === "throw" && t >= CFG.lead && t < p.fx) {
    const u = (t - CFG.lead) / CFG.flight, w = CFG.capsulePx * k;
    const x = sc.psx + (sc.tsx - sc.psx) * u, y = sc.psy + (sc.tsy - sc.psy) * u;
    const lift = (4 * u * (1 - u) * CFG.arc + 30 * (1 - u)) * k;
    g.drawImage(img(lk.sprite), x - w / 2, y - lift - w / 2, w, w);
  }
  const i = Math.floor((t - p.fx) / lk.frameMs);
  if (t >= p.fx && i < lk.frames.length) {
    const w = lk.px * k;
    g.drawImage(img(lk.frames[i]), sc.tsx - w / 2, sc.tsy - w * lk.anchor, w, w);
  }
}
function idle(tid, scene) {
  ready(sceneImages(tid, scene)).then(() => { if (!run || run.tid !== tid) draw(tid, scene, -1); });
}
function stop() {
  for (const s of sources) { try { s.stop(); } catch (e) {} }
  sources = [];
  if (run) {
    run.btn.classList.remove("on");
    const was = run; run = null;
    idle(was.tid, was.scene);
  }
}
function caption(tid, text) { document.querySelector(`.cap[data-t="${tid}"]`).textContent = text; }
function num(key) { return key.startsWith("Cartoon") ? "卡通" : "#" + key.split("_")[2]; }
function source(tid, seg) {
  if (tid === "Cartoon") return "";
  const v = chosen(`${tid}.${seg}`);
  return v === "redo" ? "（都不喜歡，先用目前那條）" : Number(v) === CFG.cur[`${tid}.${seg}`] ? "（目前那條）" : "（你選的）";
}
async function play(btn, tid, scene, seg, key) {
  const ac = audio();
  stop();
  const my = ++token, p = plan(tid, scene), solo = seg && $("solo").checked;
  const keys = {};
  for (const [s] of p.ev) keys[s] = s === seg ? key : pick(tid, s);
  const parts = p.ev.map(([s]) => `${SEG_NAME[s]} ${num(keys[s])}${s === seg ? "" : solo ? "（靜音）" : source(tid, s)}`);
  caption(tid, parts.join(" → "));
  btn.classList.add("on");
  run = { tid, scene, btn, t0: Infinity, total: p.total };
  const audible = p.ev.filter(([s]) => !solo || s === seg);
  const lk = CFG.look[tid];
  const [bufs] = await Promise.all([Promise.all(audible.map(([s]) => buffer(keys[s]))),
    ready([...sceneImages(tid, scene), lk.sprite, ...lk.frames])]);
  if (my !== token) return;
  const t0 = ac.currentTime + 0.08;
  audible.forEach(([s, at], n) => {
    const src = ac.createBufferSource();
    src.buffer = bufs[n]; src.connect(ac.destination); src.start(t0 + at / 1000);
    sources.push(src);
  });
  run.t0 = t0;
  requestAnimationFrame(tick);
}
function tick() {
  if (!run) return;
  const t = AC.currentTime >= run.t0 ? (AC.currentTime - run.t0) * 1000 : -1;
  draw(run.tid, run.scene, t);
  if (t > run.total) { const was = run; run = null; was.btn.classList.remove("on"); return; }
  requestAnimationFrame(tick);
}
document.addEventListener("click", e => {
  const b = e.target.closest("button.play, button.scene");
  if (!b) return;
  e.preventDefault(); e.stopPropagation();
  const tid = b.dataset.t;
  if (b.classList.contains("scene")) play(b, tid, b.dataset.scene, null, null);
  else play(b, tid, SEG_SCENE[b.dataset.seg], b.dataset.seg, `${tid}_${b.dataset.seg}_${b.dataset.n}`);
});
for (const c of document.querySelectorAll("canvas.stage")) { STAGE[c.dataset.t] = c; idle(c.dataset.t, "throw"); }
function render() {
  const lines = ["萬用膠囊音效挑選（__STAMP__）"];
  let changed = 0;
  for (const r of CFG.rows) {
    const v = chosen(r.slot), cur = CFG.cur[r.slot];
    if (v !== String(cur)) changed++;
    lines.push(`${r.label}：${v === "redo" ? "重做" : Number(v) === cur ? `${v}（維持目前）` : `${v}（目前 ${cur}）`}`);
  }
  $("out").value = lines.join("\\n");
  $("sum").textContent = changed ? `改了 ${changed} 列，其餘維持目前` : "目前全部維持原樣";
}
document.addEventListener("change", e => { if (e.target.type === "radio") render(); });
$("copy").addEventListener("click", async () => {
  const t = $("out");
  try { await navigator.clipboard.writeText(t.value); }
  catch (e) { t.focus(); t.select(); document.execCommand("copy"); }
  $("copy").textContent = "已複製";
  setTimeout(() => { $("copy").textContent = "複製結果"; }, 1500);
});
render();
</script>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg", default=os.path.join(bs.REPO, "temp", "e2e-vcap-fxbg-1012t"), help="fxbg-sp 收集的證據資料夾")
    a = ap.parse_args()
    cfg, sections = build(a.bg)
    stamp = datetime.date.today().strftime("%m%d")
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"vcap-sfx-pick-{stamp}.html")
    page = (PAGE.replace("__SECTIONS__", "\n".join(sections)).replace("__CFG__", json.dumps(cfg, ensure_ascii=False))
            .replace("__STAMP__", f"vcap-sfx-pick-{stamp}"))
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print(f"{os.path.relpath(dst, bs.REPO)}  {os.path.getsize(dst) / 1024:.0f} KB  {len(cfg['snd'])} clips")


if __name__ == "__main__":
    main()
