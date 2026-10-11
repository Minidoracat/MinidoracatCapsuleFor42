# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""車輛膠囊效果演示頁（第 1 版）：煙霧樣式 × 音效候選，照遊戲裡的時間軸與畫法播放，給使用者自由搭配挑選。

步驟（repo 根目錄）：
    python ~/.omp/agent/skills/elevenlabs-tts/scripts/eleven_tts.py sfx --manifest scripts/assets/sfx_v5.json \
        --out-dir temp/assets-review/sfx-v5/raw --format wav --variants 4 --trim --skip-existing
    uv run scripts/assets/design_smoke.py                 # 煙霧樣式 -> temp/assets-review/fx-v1/smoke/
    python ../pz-family-docs/scripts/e2e/pz_e2e.py run --mod-id MinidoracatVehicleCapsuleFor42 \
        --scenario .claude/skills/vehiclecapsule-e2e/scenarios/fxbg-sp --sp --scratch client1:Screenshots \
        --id vcap-fxbg-<id> --collect temp/e2e-vcap-fxbg-<id>   # 乾淨背景與螢幕座標
    uv run scripts/assets/design_fx.py [--bg temp/e2e-vcap-fxbg-<id>]
產物：temp/assets-review/fx-v1/index.html（直接用瀏覽器開檔；只用 <img>／<audio>，file:// 也能播）、
sfx/*.ogg（照 build_sfx 的整理法：剪前面靜音、淡入淡出、RMS 峰值 -18 dBFS（出車 -14）、限幅 -1 dBFS，Vorbis q5，跟 MOD 一樣）、
bg/*.jpg（背景裁切）、calib.png（遊戲內現行煙霧截圖 vs 演示頁畫法，對位檢查）。

時間軸照程式（Effects.lua、ISThrowCapsuleAction.lua、ISPressCapsuleAction.lua、Pack.lua）：
  丟出：放手時在丟的人位置播 VehicleCapsuleThrow，膠囊 0.5 s 飛到落點（拋物線，FLIGHT_MS／ARC_PX），
        落地同時出車、閃光、播 VehicleCapsulePop、煙霧開始。
  按鈕：按下動作開始時播 VehicleCapsuleButton，動作 40 單位＝0.8 s 結束時出車（同上，地上的膠囊消失）。
  收車：10 秒動作結束時車消失、膠囊掉在原地、閃光、播 VehicleCapsulePack、同一套煙霧。
煙霧：每幀 frame_ms，畫在 x = sx - w/2、y = sy - w*anchor、w = px/zoom（Effects.lua drawSmoke），一般透明度混合。
閃光：IsoLightSource 約 0.2 s。白天實測沒有亮度差（fxbg-calib-1..3 對 fxbg-throw-car，落點外圈 RGB 差 0），頁面不畫。
"""
import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_sfx as bs  # noqa: E402

REPO = bs.REPO
SR = bs.SR
OUT = os.path.join(bs.REVIEW, "fx-v1")
RAW = os.path.join(bs.REVIEW, "sfx-v5", "raw")
MOD_MEDIA = os.path.join(REPO, "MOD", "MinidoracatVehicleCapsuleFor42", "Contents", "mods", "MinidoracatVehicleCapsuleFor42",
                         "42", "media")
SOFT_ABOVE_HZ = 4000  # 頻譜重心超過這個、且提示詞是容易刺耳的音色（閃光、鈴、電子音）才柔化；嘶聲、蒸汽本來就亮，柔化會變悶
SHRILL = re.compile(r"shimmer|sparkl|twinkl|chime|blip|zap|whir|electric", re.I)

SEGMENTS = {  # 段 -> (中文, MOD 音效名, 有聲長度範圍 s)
    "Throw": ("丟出咻聲", "VehicleCapsuleThrow", (0.25, 0.9)),
    "Pop": ("出車蹦聲", "VehicleCapsulePop", (0.3, 1.7)),
    "Pack": ("收車聲", "VehicleCapsulePack", (0.4, 1.6)),
    "Button": ("按鈕聲", "VehicleCapsuleButton", (0.06, 0.7)),
}
STYLES = {  # 提示詞 id 的尾段 -> 風格名
    "Real": "寫實機械", "Real2": "寫實低沉", "SmokeGrenade": "寫實煙霧彈", "HeavyDrop": "重落塵土", "Heavy": "重落塵土",
    "Steam": "蒸汽氣壓", "Switch": "蒸汽氣壓", "Sci": "科幻傳送", "Magic": "魔法",
}
PRESETS = [  # 套組：煙霧樣式＋每段用哪個提示詞（取該提示詞評分最好的 take）
    ("卡通（目前）", "C0", {"Throw": "Current", "Pop": "Current", "Pack": "Current", "Button": "Current"}),
    ("寫實", "S1", {"Throw": "ThrowReal", "Pop": "PopReal", "Pack": "PackReal", "Button": "ButtonReal"}),
    ("塵土重落", "S2", {"Throw": "ThrowReal2", "Pop": "PopHeavyDrop", "Pack": "PackHeavy", "Button": "ButtonReal"}),
    ("蒸汽", "S3", {"Throw": "ThrowReal", "Pop": "PopSteam", "Pack": "PackSteam", "Button": "ButtonSwitch"}),
    ("科幻", "S4", {"Throw": "ThrowSci", "Pop": "PopSci", "Pack": "PackSci", "Button": "ButtonSci"}),
    ("魔法", "S5", {"Throw": "ThrowMagic", "Pop": "PopMagic", "Pack": "PackMagic", "Button": "ButtonMagic"}),
    ("衝擊環", "S6", {"Throw": "ThrowReal2", "Pop": "PopSmokeGrenade", "Pack": "PackReal", "Button": "ButtonReal"}),
]
# 遊戲常數（Effects.lua、Rules.lua、TimedActions）
FLIGHT_MS, CAPSULE_PX, ARC_PX = 500, 40, 90
PRESS_MS = 40 * 20
LEAD_MS = 600            # 每段開頭先停一下，看得到事前的畫面
CROP_W, CROP_H = 1280, 720
CROP_UP = 470            # 裁切框上緣在落點上方多少（螢幕 px，zoom 1；煙霧往上長）


def run_ff(args, data=None):
    return subprocess.run(["ffmpeg", "-v", "error", *args], input=data, capture_output=True, check=True).stdout


def encode(a, dst, target):
    """照 build_sfx.level_af 整理後寫成 Vorbis q5（跟 MOD 一樣）。"""
    run_ff(["-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0", "-af", bs.level_af(bs.stats(a), target),
            "-ac", "1", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", dst],
           a.astype("<f4").tobytes())
    return bs.stats(bs.decode(dst))


def seg_of(pid):
    return next(s for s in SEGMENTS if pid.startswith(s))


def build_sounds():
    """v5 每個 take 整理成 sfx/<id>_<n>.ogg；目前 MOD 用的四個當 Current。回傳 {sound id: 資訊}。"""
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    manifest = json.load(open(os.path.join(HERE, "sfx_v5.json"), encoding="utf-8"))
    sounds = {}
    for seg, (_, name, _) in SEGMENTS.items():
        src = os.path.join(MOD_MEDIA, "sound", "MinidoracatVehicleCapsule", name + ".ogg")
        dst = os.path.join(OUT, "sfx", f"Current_{seg}.ogg")
        shutil.copyfile(src, dst)
        s = bs.stats(bs.decode(dst))
        sounds[f"Current_{seg}"] = {"seg": seg, "prompt": "Current", "style": "目前（卡通）", "n": 0,
                                    "src": f"sfx/Current_{seg}.ogg", "active": round(s["active"], 2),
                                    "centroid": round(s["centroid"]), "soft": False, "flags": []}
    for item in manifest:
        pid, seg = item["id"], seg_of(item["id"])
        style = STYLES[pid[len(seg):]]
        lo, hi = SEGMENTS[seg][2]
        target = bs.target_db(SEGMENTS[seg][1])
        for n in range(1, 9):
            src = os.path.join(RAW, f"{pid}_{n}.wav")
            if not os.path.exists(src):
                break
            a = bs.decode(src)
            s0 = bs.stats(a)
            soft = s0["centroid"] > SOFT_ABOVE_HZ and SHRILL.search(item["text"]) is not None
            if soft:
                a = bs.soften(a)
            sid = f"{pid}_{n}"
            s = encode(a, os.path.join(OUT, "sfx", sid + ".ogg"), target)
            flags = []
            if not lo <= s["active"] <= hi:
                flags.append(f"長度 {s['active']:.2f}s")
            if s["peak_db"] < -20:
                flags.append("太小聲")
            sounds[sid] = {"seg": seg, "prompt": pid, "style": style, "n": n, "src": f"sfx/{sid}.ogg",
                           "active": round(s["active"], 2), "centroid": round(s["centroid"]), "soft": soft,
                           "flags": flags, "text": item["text"]}
            print(f"{sid:22s} {style:6s} active {s['active']:.2f}s centroid {s['centroid']:5.0f} Hz"
                  f"{' soft' if soft else ''}{' ' + ','.join(flags) if flags else ''}")
    return sounds


def best_take(sounds, prompt):
    """套組用：長度合格的優先，再挑頻譜重心低的（較不刺耳）。"""
    cands = [k for k, v in sounds.items() if v["prompt"] == prompt]
    return min(cands, key=lambda k: (bool(sounds[k]["flags"]), sounds[k]["centroid"])) if cands else None


def load_smoke():
    path = os.path.join(OUT, "smoke", "styles.json")
    styles = json.load(open(path, encoding="utf-8"))
    for st in styles:
        st["files"] = [f"smoke/{st['id']}/{st['id']}_{i:02d}.png" for i in range(1, st["frames"] + 1)]
        missing = [f for f in st["files"] if not os.path.exists(os.path.join(OUT, f))]
        if missing:
            sys.exit(f"smoke {st['id']}: missing {missing[0]}")
    return styles


COORD = re.compile(r"\[E2E\] COORD (\S+) (.*)")


def load_bg(bg_dir):
    """E2E 的 COORD 行與截圖 -> 每個場景的背景裁切（JPEG）與裁切內座標。"""
    log = open(os.path.join(bg_dir, "client1", "console.txt"), encoding="utf-8", errors="replace").read()
    coords = {}
    for m in COORD.finditer(log):
        coords[m.group(1)] = {k: float(v) for k, v in re.findall(r"(\w+)=([-\d.]+)", m.group(2))}
    shots = os.path.join(bg_dir, "client1", "Screenshots")
    os.makedirs(os.path.join(OUT, "bg"), exist_ok=True)
    scenes = {}
    for key, before, after, cname in (("throw", "throw-empty", "throw-car", "throw-empty"),
                                      ("press", "press-capsule", "press-car", "press-capsule"),
                                      ("pack", "pack-car", "pack-empty", "pack-car")):
        c = coords[cname]
        z = c["zoom"]
        im = Image.open(os.path.join(shots, f"fxbg-{before}.png"))
        sw, sh = im.size
        x0 = int(round(min(max(c["tsx"] - CROP_W / 2, 0), sw - CROP_W)))
        y0 = int(round(min(max(c["tsy"] - CROP_UP / z, 0), sh - CROP_H)))
        box = (x0, y0, x0 + CROP_W, y0 + CROP_H)
        for tag in (before, after):
            Image.open(os.path.join(shots, f"fxbg-{tag}.png")).convert("RGB").crop(box).save(
                os.path.join(OUT, "bg", f"{tag}.jpg"), quality=92)
        scenes[key] = {"before": f"bg/{before}.jpg", "after": f"bg/{after}.jpg", "zoom": z,
                       "tsx": c["tsx"] - x0, "tsy": c["tsy"] - y0, "psx": c["psx"] - x0, "psy": c["psy"] - y0,
                       "csx": c["csx"] - x0, "csy": c["csy"] - y0, "shot": [sw, sh], "crop": [x0, y0]}
    calib = {"coord": coords.get("calib"), "ages": [int(a) for a in re.findall(r"\[E2E\] CALIB n=\d+ age=(\d+)", log)]}
    return scenes, calib, shots


def calib_compare(calib, shots, c0):
    """遊戲內現行煙霧（fxbg-calib-n.png）旁邊放演示頁畫法（同一張無煙背景＋同一幀），確認錨點與大小。"""
    c = calib["coord"]
    if not c or not calib["ages"]:
        return
    z = c["zoom"]
    base = Image.open(os.path.join(shots, "fxbg-throw-car.png")).convert("RGBA")
    rows = []
    for n, age in enumerate(calib["ages"], 1):
        game = Image.open(os.path.join(shots, f"fxbg-calib-{n}.png")).convert("RGBA")
        emu = base.copy()
        i = age // c0["frame_ms"]
        if i < c0["frames"]:
            w = int(round(c0["px"] / z))
            fr = Image.open(os.path.join(OUT, c0["files"][i])).convert("RGBA").resize((w, w), Image.BILINEAR)
            emu.alpha_composite(fr, (int(round(c["tsx"] - w / 2)), int(round(c["tsy"] - w * c0["anchor"]))))
        box = (int(c["tsx"] - 330), int(c["tsy"] - 330), int(c["tsx"] + 330), int(c["tsy"] + 170))
        row = Image.new("RGBA", (1320, 500))
        row.paste(game.crop(box), (0, 0))
        row.paste(emu.crop(box), (660, 0))
        rows.append(row)
    sheet = Image.new("RGB", (1320, 500 * len(rows)))
    for k, r in enumerate(rows):
        sheet.paste(r, (0, 500 * k))
    sheet.save(os.path.join(OUT, "calib.png"))
    print("calib ->", os.path.relpath(os.path.join(OUT, "calib.png"), REPO), "ages", calib["ages"])


def page(cfg):
    e = html.escape
    data = json.dumps(cfg, ensure_ascii=False)
    return PAGE.replace("/*CFG*/", data).replace("@TITLE@", e(cfg["title"]))


PAGE = r"""<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>@TITLE@</title>
<style>
:root{color-scheme:dark;--bg:#121418;--panel:#1b1e24;--line:#2b3038;--fg:#e9e7e3;--mut:#9aa1a9;--acc:#e3a94f;--ok:#7fc58b;--warn:#e0b05c}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 "Segoe UI","Microsoft JhengHei UI","Microsoft JhengHei",sans-serif}
header{padding:14px 20px 4px;max-width:1880px;margin:0 auto}
h1{font-size:20px;margin:0 0 4px}
header p{margin:2px 0;color:var(--mut);font-size:13.5px}
main{display:grid;grid-template-columns:minmax(0,1fr) 420px;gap:18px;padding:10px 20px 24px;max-width:1880px;margin:0 auto}
@media (max-width:1180px){main{grid-template-columns:1fr}}
.tabs{display:flex;gap:6px;margin-bottom:8px}
.tabs button,.chip{background:var(--panel);color:var(--fg);border:1px solid var(--line);border-radius:7px;padding:6px 14px;font:inherit;cursor:pointer}
.tabs button[aria-pressed=true],.chip[aria-pressed=true]{border-color:var(--acc);color:var(--acc)}
canvas{display:block;width:100%;height:auto;border-radius:8px;background:#000}
.bar{display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin-top:10px}
.play{background:var(--acc);color:#1a1205;border:0;border-radius:8px;padding:9px 22px;font:600 16px inherit;font-family:inherit;cursor:pointer}
label.t{display:flex;align-items:center;gap:6px;color:var(--mut);font-size:14px}
.tl{position:relative;height:30px;margin-top:10px;background:var(--panel);border:1px solid var(--line);border-radius:6px;overflow:hidden}
.tl .seg{position:absolute;top:0;bottom:0;display:flex;align-items:center;padding:0 6px;font-size:12px;white-space:nowrap;overflow:hidden;border-left:2px solid rgba(255,255,255,.35)}
.tl .cur{position:absolute;top:0;bottom:0;width:2px;background:var(--acc)}
.pick{margin-top:12px;padding:10px 12px;background:var(--panel);border:1px solid var(--line);border-radius:8px;font-size:14px}
.pick code{font:13px Consolas,monospace;color:var(--acc)}
aside{display:flex;flex-direction:column;gap:14px}
aside section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px}
aside h2{font-size:15px;margin:0 0 8px}
.presets{display:flex;flex-wrap:wrap;gap:6px}
.styles{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.st{display:flex;gap:8px;align-items:center;background:#15181d;border:1px solid var(--line);border-radius:8px;padding:6px;cursor:pointer;text-align:left;color:var(--fg);font:inherit}
.st[aria-pressed=true]{border-color:var(--acc)}
.st img{width:54px;height:54px;object-fit:contain;background:#3a3f46;border-radius:5px;flex:none}
.st b{display:block;font-size:14px}.st small{color:var(--mut);font-size:12px;line-height:1.35}
.snd{display:grid;grid-template-columns:76px 1fr 34px;gap:6px;align-items:center;margin:6px 0}
.snd span{color:var(--mut);font-size:13.5px}
select{width:100%;background:#15181d;color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:5px;font:inherit;font-size:13.5px}
.mini{background:#15181d;color:var(--fg);border:1px solid var(--line);border-radius:6px;height:30px;cursor:pointer}
.note{color:var(--mut);font-size:12.5px;margin:6px 0 0}
.flag{color:var(--warn)}
</style></head><body>
<header>
<h1>@TITLE@</h1>
<p>背景是遊戲內實際截圖（正午、晴天、預設縮放），煙霧照遊戲的畫法與大小疊上去，時間軸照程式：丟出的膠囊飛 0.5 秒落地出車、按鈕 0.8 秒後出車、收車在動作結束那一刻車消失。</p>
<p>音效都對齊響度（出車那段 -14 dBFS，其他 -18 dBFS），遊戲裡還會依距離變小聲。遊戲同時會亮一下燈光（約 0.2 秒），白天實測看不出來，頁面不畫。「已柔化」＝原檔太亮，先削了高頻。慢動作不播聲音。</p>
</header>
<main>
<div>
  <div class="tabs" id="tabs"></div>
  <canvas id="cv" width="1280" height="720"></canvas>
  <div class="tl" id="tl"></div>
  <div class="bar">
    <button class="play" id="play">▶ 播放（空白鍵）</button>
    <label class="t"><input type="checkbox" id="slow"> 慢動作 ¼</label>
    <label class="t"><input type="checkbox" id="loop"> 連續播放</label>
    <label class="t">音量 <input type="range" id="vol" min="0" max="1" step="0.05" value="0.8"></label>
  </div>
  <div class="pick">目前組合：<code id="pickText"></code> <button class="mini" id="copy" style="padding:0 10px">複製</button>
    <p class="note">挑好後把這串貼給我就行；也可以只說「煙霧要 S2、出車要 PopHeavyDrop_3」這樣。</p></div>
</div>
<aside>
  <section><h2>套組（一鍵換整組）</h2><div class="presets" id="presets"></div></section>
  <section><h2>煙霧樣式</h2><div class="styles" id="styles"></div></section>
  <section><h2>音效</h2><div id="sounds"></div>
    <p class="note">▶ 單獨試聽。選單依風格分組，# 後面是同一句提示詞的第幾個版本。</p></section>
</aside>
</main>
<script>const CFG = /*CFG*/;</script>
<script>
"use strict";
const $ = id => document.getElementById(id);
const cv = $("cv"), g = cv.getContext("2d");
const IMG = {}, AUD = {};
const img = src => { if (!IMG[src]) { const i = new Image(); i.src = src; IMG[src] = i; } return IMG[src]; };
const aud = src => { if (!AUD[src]) { const a = new Audio(src); a.preload = "auto"; AUD[src] = a; } return AUD[src]; };
const S = { scene: "throw", smoke: CFG.presets[1].smoke, snd: Object.assign({}, CFG.presets[1].snd), slow: false, loop: false, vol: 0.8 };
let run = null;
const style = () => CFG.smoke.find(s => s.id === S.smoke);
const sc = () => CFG.scenes[S.scene];
const smokeMs = () => style().frames * style().frame_ms;

function plan() {
  const L = CFG.lead;
  if (S.scene === "throw") return { fx: L + CFG.flight, total: L + CFG.flight + smokeMs() + 500,
    segs: [["Throw", L, L + CFG.flight, "咻（飛 0.5 秒）"], ["Pop", L + CFG.flight, L + CFG.flight + smokeMs(), "蹦＋煙霧＋出車"]] };
  if (S.scene === "press") return { fx: L + CFG.press, total: L + CFG.press + smokeMs() + 500,
    segs: [["Button", L, L + CFG.press, "按鈕（動作 0.8 秒）"], ["Pop", L + CFG.press, L + CFG.press + smokeMs(), "蹦＋煙霧＋出車"]] };
  return { fx: L, total: L + smokeMs() + 600, segs: [["Pack", L, L + smokeMs(), "收車聲＋煙霧（車消失）"]] };
}

function play(seg) {
  const s = CFG.sounds[S.snd[seg]];
  if (!s) return;
  const a = aud(s.src);
  a.pause(); a.currentTime = 0; a.volume = S.vol; a.play().catch(() => {});
}

function start() { run = { t0: performance.now(), fired: {} }; }

function drawFlight(d, t) {
  const u = Math.min(t / CFG.flight, 1), z = d.zoom;
  const x = d.psx + (d.tsx - d.psx) * u, y = d.psy + (d.tsy - d.psy) * u;
  const lift = (4 * u * (1 - u) * CFG.arc + 30 * (1 - u)) / z, w = CFG.capsulePx / z;
  g.drawImage(img(CFG.capsule), x - w / 2, y - lift - w / 2, w, w);
}

function drawSmoke(d, age) {
  const st = style(), i = Math.floor(age / st.frame_ms);
  if (age < 0 || i >= st.frames) return;
  const w = st.px / d.zoom;
  g.drawImage(img(st.files[i]), d.tsx - w / 2, d.tsy - w * st.anchor, w, w);
}

function frame(now) {
  const d = sc(), p = plan();
  const t = run ? (now - run.t0) * (S.slow ? 0.25 : 1) : -1;
  const swapped = run && t >= p.fx;
  g.globalCompositeOperation = "source-over";
  g.drawImage(img(swapped ? d.after : d.before), 0, 0);
  if (run) {
    if (S.scene === "throw" && t >= CFG.lead && t < p.fx) drawFlight(d, t - CFG.lead);
    drawSmoke(d, t - p.fx);
    for (const [seg, t0] of p.segs) {
      if (t >= t0 && !run.fired[seg]) { run.fired[seg] = 1; if (!S.slow) play(seg); }
    }
    if (t > p.total) { if (S.loop) start(); else run = null; }
  }
  $("cur").style.left = run ? (100 * Math.min(t / p.total, 1)) + "%" : "-4px";
  requestAnimationFrame(frame);
}

function renderTimeline() {
  const p = plan(), tl = $("tl");
  tl.innerHTML = "";
  const colors = { Throw: "#3b6f9e", Pop: "#a0543b", Pack: "#6a4f9a", Button: "#4c8a5a" };
  for (const [seg, a, b, label] of p.segs) {
    const el = document.createElement("div");
    el.className = "seg"; el.textContent = label;
    el.style.left = (100 * a / p.total) + "%"; el.style.width = (100 * (b - a) / p.total) + "%";
    el.style.background = colors[seg]; tl.appendChild(el);
  }
  const cur = document.createElement("div"); cur.className = "cur"; cur.id = "cur"; tl.appendChild(cur);
}

function pickText() {
  return `${S.smoke}｜咻 ${S.snd.Throw}｜蹦 ${S.snd.Pop}｜收 ${S.snd.Pack}｜鈕 ${S.snd.Button}`;
}

function refresh() {
  for (const b of $("tabs").children) b.setAttribute("aria-pressed", b.dataset.k === S.scene);
  for (const b of $("styles").children) b.setAttribute("aria-pressed", b.dataset.k === S.smoke);
  for (const b of $("presets").children) {
    const pr = CFG.presets[+b.dataset.i];
    b.setAttribute("aria-pressed", pr.smoke === S.smoke && Object.keys(pr.snd).every(k => pr.snd[k] === S.snd[k]));
  }
  for (const seg of Object.keys(CFG.segments)) $("sel" + seg).value = S.snd[seg];
  $("pickText").textContent = pickText();
  style().files.forEach(img);
  Object.values(S.snd).forEach(id => CFG.sounds[id] && aud(CFG.sounds[id].src));
  renderTimeline();
}

function build() {
  for (const [k, label] of [["throw", "丟出"], ["press", "按下按鈕"], ["pack", "收車"]]) {
    const b = document.createElement("button"); b.textContent = label; b.dataset.k = k;
    b.onclick = () => { S.scene = k; run = null; refresh(); start(); };
    $("tabs").appendChild(b);
  }
  CFG.presets.forEach((pr, i) => {
    const b = document.createElement("button"); b.className = "chip"; b.textContent = pr.name; b.dataset.i = i;
    b.onclick = () => { S.smoke = pr.smoke; S.snd = Object.assign({}, pr.snd); refresh(); start(); };
    $("presets").appendChild(b);
  });
  for (const st of CFG.smoke) {
    const b = document.createElement("button"); b.className = "st"; b.dataset.k = st.id;
    const th = st.files[Math.min(st.frames - 1, Math.round(st.frames * 0.3))];
    b.innerHTML = `<img src="${th}" alt=""><span><b>${st.id} ${st.name}</b><small>${st.desc}<br>${st.frames} 幀 × ${st.frame_ms} ms</small></span>`;
    b.onclick = () => { S.smoke = st.id; refresh(); start(); };
    $("styles").appendChild(b);
  }
  for (const [seg, label] of Object.entries(CFG.segments)) {
    const row = document.createElement("div"); row.className = "snd";
    const sel = document.createElement("select"); sel.id = "sel" + seg;
    const groups = {};
    for (const [id, s] of Object.entries(CFG.sounds)) {
      if (s.seg !== seg) continue;
      if (!groups[s.style]) { groups[s.style] = document.createElement("optgroup"); groups[s.style].label = s.style; sel.appendChild(groups[s.style]); }
      const o = document.createElement("option"); o.value = id;
      const tag = s.prompt === "Current" ? "目前使用" : `${s.prompt} #${s.n}`;
      o.textContent = `${tag}（${s.active.toFixed(2)} s${s.soft ? "，已柔化" : ""}${s.flags.length ? "，" + s.flags.join("、") : ""}）`;
      groups[s.style].appendChild(o);
    }
    sel.onchange = () => { S.snd[seg] = sel.value; refresh(); play(seg); };
    const btn = document.createElement("button"); btn.className = "mini"; btn.textContent = "▶"; btn.title = "單獨試聽";
    btn.onclick = () => play(seg);
    const lab = document.createElement("span"); lab.textContent = label;
    row.append(lab, sel, btn); $("sounds").appendChild(row);
  }
  $("play").onclick = start;
  $("slow").onchange = e => { S.slow = e.target.checked; };
  $("loop").onchange = e => { S.loop = e.target.checked; };
  $("vol").oninput = e => { S.vol = +e.target.value; };
  $("copy").onclick = () => navigator.clipboard && navigator.clipboard.writeText(pickText());
  document.addEventListener("keydown", e => { if (e.code === "Space" && e.target.tagName !== "SELECT") { e.preventDefault(); start(); } });
  img(CFG.capsule);
  for (const d of Object.values(CFG.scenes)) { img(d.before); img(d.after); }
  refresh();
  requestAnimationFrame(frame);
}
build();
</script>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg", default=os.path.join(REPO, "temp", "e2e-vcap-fxbg-1012a"), help="fxbg-sp 收集的證據資料夾")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    smoke = load_smoke()
    scenes, calib, shots = load_bg(a.bg)
    calib_compare(calib, shots, next(s for s in smoke if s["id"] == "C0"))
    sounds = build_sounds()
    shutil.copyfile(os.path.join(MOD_MEDIA, "textures", "Item_MinidoracatVehicleCapsuleCartoonLoaded.png"),
                    os.path.join(OUT, "capsule.png"))
    presets = []
    for name, sm, snd in PRESETS:
        if not any(s["id"] == sm for s in smoke):
            continue
        pick = {seg: (f"Current_{seg}" if p == "Current" else best_take(sounds, p)) for seg, p in snd.items()}
        presets.append({"name": name, "smoke": sm, "snd": pick})
    cfg = {"title": "車輛膠囊效果演示（第 1 版）", "lead": LEAD_MS, "flight": FLIGHT_MS, "press": PRESS_MS, "arc": ARC_PX,
           "capsulePx": CAPSULE_PX, "capsule": "capsule.png",
           "segments": {k: v[0] for k, v in SEGMENTS.items()}, "smoke": smoke, "scenes": scenes, "sounds": sounds,
           "presets": presets}
    with open(os.path.join(OUT, "index.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(page(cfg))
    print("->", os.path.relpath(os.path.join(OUT, "index.html"), REPO), f"{len(sounds)} sounds, {len(smoke)} smoke styles")


if __name__ == "__main__":
    main()
