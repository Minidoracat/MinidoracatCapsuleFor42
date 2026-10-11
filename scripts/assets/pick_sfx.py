# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""車輛膠囊七種款式的音效挑選頁：卡通以外六款 × 四段（丟出、彈開、收車、按鈕），每段 4 個 ElevenLabs 候選。

2026-10-12 使用者在設計稿 vcap-types-1012 選「28 段全部由你挑」，補一句「卡通的音效就先維持吧」：卡通四段只當參考。
候選：第 5 版提示詞 scripts/assets/sfx_v5.json（temp/assets-review/sfx-v5/raw），以及原本借用別款的 5 段新提示詞
scripts/assets/sfx_v6.json（sfx-v6/raw）。每條照 build_sfx.write 的整理（design_fx.py 同一條柔化規則、level_af、彈開
-14 dBFS）後轉 MP3 內嵌，聽到的就是裝進 MOD 的樣子。「目前」是 build_sfx.SPEC 現在選的那條。

    uv run scripts/assets/pick_sfx.py      # 寫 temp/assets-review/sfx-pick/vcap-sfx-pick-<MMDD>.html
    orca artifacts share <那個檔> --json   # 使用者在手機上聽、挑，複製結果貼回
選定後把 build_sfx.SPEC 改成 "v5:<ID>_<n>" 或 "v6:<ID>_<n>"，再 `uv run scripts/assets/build_sfx.py --write <名稱>`。
"""
import base64
import datetime
import html
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_sfx as bs  # noqa: E402

OUT = os.path.join(bs.REVIEW, "sfx-pick")
ICONS = os.path.join(bs.REPO, "docs", "design", "types")
SOUNDS = os.path.join(bs.OUT)
SOFT_ABOVE_HZ = 4000  # design_fx.py 同一條：頻譜重心超過、而且提示詞是容易刺耳的音色才柔化
SHRILL = re.compile(r"shimmer|sparkl|twinkl|chime|blip|zap|whir|electric", re.I)

TYPES = [  # id, 中文, 效果說明（沙盒 EffectStyle 的說明文字）
    ("Real", "寫實", "灰色煙霧，機械與氣壓聲"),
    ("Dust", "塵土", "塵土貼地炸開，重物落地聲"),
    ("Steam", "蒸汽", "白色蒸氣，蒸汽噴發聲"),
    ("SciFi", "科幻", "光柱與地面光環，能量聲"),
    ("Magic", "魔法", "淡紫色煙霧與星芒，魔法聲"),
    ("Shock", "衝擊", "一閃白光與地面衝擊波，煙霧彈聲"),
]
ACTIONS = [("Throw", "丟出"), ("Pop", "彈開"), ("Pack", "收車"), ("Button", "按鈕")]
RANGE = {"Throw": bs.THROW, "Pop": bs.POP, "Pack": bs.PACK, "Button": bs.BUTTON}
# (款式, 段) -> (MOD 音效名, 候選版本, 提示詞 id)
SLOTS = {
    ("Real", "Throw"): ("VehicleCapsuleThrowReal", "v5", "ThrowReal"),
    ("Real", "Pop"): ("VehicleCapsulePopReal", "v5", "PopReal"),
    ("Real", "Pack"): ("VehicleCapsulePackReal", "v5", "PackReal"),
    ("Real", "Button"): ("VehicleCapsuleButtonReal", "v5", "ButtonReal"),
    ("Dust", "Throw"): ("VehicleCapsuleThrowReal2", "v5", "ThrowReal2"),
    ("Dust", "Pop"): ("VehicleCapsulePopHeavyDrop", "v5", "PopHeavyDrop"),
    ("Dust", "Pack"): ("VehicleCapsulePackHeavy", "v5", "PackHeavy"),
    ("Dust", "Button"): ("VehicleCapsuleButtonDust", "v6", "ButtonDust"),
    ("Steam", "Throw"): ("VehicleCapsuleThrowSteam", "v6", "ThrowSteam"),
    ("Steam", "Pop"): ("VehicleCapsulePopSteam", "v5", "PopSteam"),
    ("Steam", "Pack"): ("VehicleCapsulePackSteam", "v5", "PackSteam"),
    ("Steam", "Button"): ("VehicleCapsuleButtonSwitch", "v5", "ButtonSwitch"),
    ("SciFi", "Throw"): ("VehicleCapsuleThrowSci", "v5", "ThrowSci"),
    ("SciFi", "Pop"): ("VehicleCapsulePopSci", "v5", "PopSci"),
    ("SciFi", "Pack"): ("VehicleCapsulePackSci", "v5", "PackSci"),
    ("SciFi", "Button"): ("VehicleCapsuleButtonSci", "v5", "ButtonSci"),
    ("Magic", "Throw"): ("VehicleCapsuleThrowMagic", "v5", "ThrowMagic"),
    ("Magic", "Pop"): ("VehicleCapsulePopMagic", "v5", "PopMagic"),
    ("Magic", "Pack"): ("VehicleCapsulePackMagic", "v5", "PackMagic"),
    ("Magic", "Button"): ("VehicleCapsuleButtonMagic", "v5", "ButtonMagic"),
    ("Shock", "Throw"): ("VehicleCapsuleThrowShock", "v6", "ThrowShock"),
    ("Shock", "Pop"): ("VehicleCapsulePopSmokeGrenade", "v5", "PopSmokeGrenade"),
    ("Shock", "Pack"): ("VehicleCapsulePackShock", "v6", "PackShock"),
    ("Shock", "Button"): ("VehicleCapsuleButtonShock", "v6", "ButtonShock"),
}


def mp3(args, data=None):
    """ffmpeg → MP3 96 kbps 單聲道（手機瀏覽器都能播）的 bytes。"""
    return subprocess.run(["ffmpeg", "-v", "error", *args, "-ac", "1", "-ar", str(bs.SR), "-c:a", "libmp3lame",
                           "-b:a", "96k", "-map_metadata", "-1", "-f", "mp3", "pipe:1"],
                          input=data, capture_output=True, check=True).stdout


def candidate(name, path, text, seg):
    """整理一條候選，回傳 (MP3 bytes, 有聲長度, 註記)。"""
    a = bs.decode(path)
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


def build():
    prompts = {}
    for v in ("v5", "v6"):
        for it in json.load(open(os.path.join(HERE, f"sfx_{v}.json"), encoding="utf-8")):
            prompts[(v, it["id"])] = it["text"]
    snd, rows_js = {}, []
    ref = []
    for seg, label in ACTIONS:
        src = os.path.join(SOUNDS, f"VehicleCapsule{seg}.ogg")
        key = f"Cartoon_{seg}"
        snd[key] = data_uri(mp3(["-i", src]), "audio/mpeg")
        ref.append(f'<button type="button" class="play" data-snd="{key}" aria-label="播放 卡通 {label}">▶ {label}</button>')
    sections = []
    for tid, tname, desc in TYPES:
        icon = os.path.join(ICONS, f"{tid}-loaded.png")
        img = data_uri(open(icon, "rb").read(), "image/png") if os.path.exists(icon) else ""
        rows = []
        for seg, label in ACTIONS:
            name, ver, pid = SLOTS[(tid, seg)]
            cur = str(bs.SPEC.get(name, (None, ""))[1] or "")
            cur_n = int(cur.rsplit("_", 1)[1]) if cur.startswith(ver + ":") else None
            slot = f"{tid}.{seg}"
            chips = []
            for n in range(1, 5):
                path = os.path.join(bs.REVIEW, f"sfx-{ver}", "raw", f"{pid}_{n}.wav")
                data, active, note = candidate(name, path, prompts[(ver, pid)], seg)
                key = f"{tid}_{seg}_{n}"
                snd[key] = data_uri(data, "audio/mpeg")
                tag = '<span class="cur">目前</span>' if n == cur_n else ""
                warn = f'<span class="warn">{note}</span>' if note else ""
                checked = " checked" if n == cur_n else ""
                chips.append(
                    f'<label class="chip"><input type="radio" name="{slot}" value="{n}"{checked}>'
                    f'<button type="button" class="play" data-snd="{key}" aria-label="播放 {tname} {label} 候選 {n}">▶ {n}</button>'
                    f'<span class="len">{active:.1f}s</span>{warn}{tag}</label>')
                print(f"{slot:14s} {n}  {active:.2f}s {note}")
            chips.append(f'<label class="chip redo"><input type="radio" name="{slot}" value="redo">都不喜歡</label>')
            fresh = "" if cur_n else '<span class="new">新</span>'
            rows.append(f'<div class="row"><div class="seg">{label}{fresh}</div><div class="chips">{"".join(chips)}</div></div>')
            rows_js.append({"slot": slot, "label": f"{tname}・{label}", "cur": cur_n})
        head = f'<img src="{img}" width="32" height="32" alt="">' if img else ""
        sections.append(f'<section><h2>{head}{tname}<small>{html.escape(desc)}</small></h2>{"".join(rows)}</section>')
    return snd, rows_js, ref, sections


PAGE = """<!doctype html>
<html lang="zh-Hant-TW"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>車輛膠囊音效挑選</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; font: 15px/1.5 "Microsoft JhengHei", "Noto Sans TC", "PingFang TC", system-ui, sans-serif; background: #17181b; color: #ececec; }
  main { max-width: 760px; margin: 0 auto; padding: 16px 14px 48px; }
  h1 { font-size: 20px; margin: 0 0 6px; }
  .intro { color: #c4c4c4; font-size: 14px; margin: 0 0 14px; }
  .intro li { margin: 2px 0; }
  section { background: #222429; border: 1px solid #34363c; border-radius: 10px; padding: 10px 12px; margin: 12px 0; }
  h2 { display: flex; align-items: center; gap: 8px; font-size: 17px; margin: 0 0 6px; }
  h2 img { image-rendering: pixelated; }
  h2 small { font-size: 13px; font-weight: 400; color: #b8b8b8; }
  .row { display: grid; grid-template-columns: 52px 1fr; gap: 8px; align-items: center; padding: 6px 0; border-top: 1px solid #30323a; }
  .seg { font-weight: 600; }
  .new { display: inline-block; margin-inline-start: 4px; font-size: 11px; padding: 0 5px; border-radius: 8px; background: #ffd966; color: #1a1405; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .chip { display: inline-flex; align-items: center; gap: 6px; min-height: 44px; padding: 0 8px; border: 1px solid #4a4d55; border-radius: 8px; background: #1b1c20; }
  .chip:has(input:checked) { border-color: #ffd966; background: #2c2a1c; }
  .chip input { width: 18px; height: 18px; margin: 0; accent-color: #ffd966; }
  .play { min-width: 52px; min-height: 36px; border: 1px solid #6a6d75; border-radius: 6px; background: #2f3138; color: #fff; font-size: 14px; }
  .play.on { background: #ffd966; color: #1a1405; border-color: #ffd966; }
  .len { font-size: 12px; color: #b8b8b8; font-variant-numeric: tabular-nums; }
  .warn { font-size: 12px; color: #ffb38a; }
  .cur { font-size: 11px; padding: 0 5px; border: 1px solid #9fd39d; color: #9fd39d; border-radius: 8px; }
  .redo { color: #d0d0d0; font-size: 14px; }
  .ref { display: flex; flex-wrap: wrap; gap: 6px; }
  .out { position: sticky; bottom: 0; background: #17181b; padding: 10px 0 4px; border-top: 1px solid #34363c; }
  textarea { width: 100%; box-sizing: border-box; height: 76px; background: #0f1012; color: #ececec; border: 1px solid #4a4d55; border-radius: 8px; font: 13px/1.5 ui-monospace, Consolas, monospace; padding: 8px; }
  .bar { display: flex; gap: 10px; align-items: center; margin-top: 6px; }
  .copy { min-height: 44px; padding: 0 16px; border: 0; border-radius: 8px; background: #ffd966; color: #1a1405; font-weight: 700; font-size: 15px; }
  .left { color: #ffb38a; font-size: 14px; }
</style>
<body><main>
<h1>車輛膠囊音效挑選：六款 × 四段</h1>
<ul class="intro">
  <li>按 ▶ 試聽，每一列選一個。數字後面是有聲長度；丟出最好在 0.9 秒內（膠囊飛 0.5 秒）。</li>
  <li>「目前」是 MOD 現在用的那條。標「新」的 5 列原本借用別款的聲音，這次新錄，沒有預選。</li>
  <li>「都不喜歡」：那一列我會重寫提示詞再生成一批。</li>
  <li>選完按最下面「複製結果」，貼回對話。<b>重新整理會清掉選擇</b>，請當場複製。</li>
</ul>
<section><h2>卡通<small>維持現在的四段，只當參考</small></h2><div class="ref">__REF__</div></section>
__SECTIONS__
<div class="out">
  <textarea id="out" readonly aria-label="挑選結果"></textarea>
  <div class="bar"><button type="button" class="copy" id="copy">複製結果</button><span class="left" id="left"></span></div>
</div>
</main>
<script>
const SND = __SND__;
const ROWS = __ROWS__;
const audio = new Audio();
let playing = null;
document.addEventListener("click", e => {
  const b = e.target.closest("button.play");
  if (!b) return;
  e.preventDefault(); e.stopPropagation();
  audio.pause();
  if (playing) playing.classList.remove("on");
  audio.src = SND[b.dataset.snd]; audio.currentTime = 0; audio.play();
  playing = b; b.classList.add("on");
});
audio.addEventListener("ended", () => { if (playing) playing.classList.remove("on"); playing = null; });
function render() {
  const lines = ["車輛膠囊音效挑選（__STAMP__）"];
  let left = 0;
  for (const r of ROWS) {
    const v = (document.querySelector(`input[name="${r.slot}"]:checked`) || {}).value;
    if (!v) { left++; lines.push(`${r.label}：未選`); continue; }
    if (v === "redo") { lines.push(`${r.label}：重做`); continue; }
    const note = r.cur ? (Number(v) === r.cur ? "（維持目前）" : `（目前 ${r.cur}）`) : "（新）";
    lines.push(`${r.label}：${v}${note}`);
  }
  document.getElementById("out").value = lines.join("\\n");
  document.getElementById("left").textContent = left ? `還有 ${left} 列沒選` : "全部選好了";
}
document.addEventListener("change", render);
document.getElementById("copy").addEventListener("click", async () => {
  const t = document.getElementById("out");
  try { await navigator.clipboard.writeText(t.value); }
  catch (e) { t.focus(); t.select(); document.execCommand("copy"); }
  document.getElementById("copy").textContent = "已複製";
  setTimeout(() => { document.getElementById("copy").textContent = "複製結果"; }, 1500);
});
render();
</script>
</body></html>
"""


def main():
    snd, rows, ref, sections = build()
    stamp = datetime.date.today().strftime("%m%d")
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"vcap-sfx-pick-{stamp}.html")
    page = (PAGE.replace("__REF__", "".join(ref)).replace("__SECTIONS__", "\n".join(sections))
            .replace("__SND__", json.dumps(snd)).replace("__ROWS__", json.dumps(rows, ensure_ascii=False))
            .replace("__STAMP__", f"vcap-sfx-pick-{stamp}"))
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print(f"{os.path.relpath(dst, bs.REPO)}  {os.path.getsize(dst) / 1024:.0f} KB  {len(snd)} clips")


if __name__ == "__main__":
    main()
