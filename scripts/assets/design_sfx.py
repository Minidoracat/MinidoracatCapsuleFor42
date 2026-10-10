# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""車輛膠囊音效第 2 版候選：從 ElevenLabs 原始 take 加程式合成元素，重建所有候選與試聽頁。

步驟（repo 根目錄）：
    python ~/.omp/agent/skills/elevenlabs-tts/scripts/eleven_tts.py sfx --manifest scripts/assets/sfx_v2.json \
        --out-dir temp/assets-review/sfx-v2/raw --format wav --variants 4 --trim
    uv run scripts/assets/design_sfx.py       # 寫 temp/assets-review/sfx-v2/<Name>_<ID>.wav、<Name>_now.wav、index.html
    uv run scripts/assets/build_sfx.py        # 列表模式檢查長度；選定後 --write --pick <Name>=v2:<ID>

每條候選都照 build_sfx.level_af 整理（剪前面靜音、淡入淡出、RMS 峰值 -18 dBFS、限幅 -1 dBFS），試聽才公平。
ElevenLabs 的 take 高頻偏多（開瓶嘶聲、按鈕喀聲重心 7–10 kHz），SOFT 照 elevenlabs-tts 技能的刺耳處理削掉。
合成元素的音高壓在 1 kHz 上下再低通：純音在高頻怎麼削都刺耳（技能 2026-10-06 的教訓）。
"""
import html
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_sfx as bs  # noqa: E402

SR = bs.SR
V2 = bs.V2
RAW = os.path.join(V2, "raw")
SOFT = "highpass=f=80,equalizer=f=3000:t=o:w=1.5:g=-5,equalizer=f=6500:t=o:w=1:g=-4,lowpass=f=5000,lowpass=f=5000"
rng = np.random.default_rng(42)


def ff(a, af):
    """numpy 陣列過一串 ffmpeg 濾鏡（32-bit float 進出，中途不削波）。"""
    out = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
                          "-af", af, "-f", "f32le", "pipe:1"],
                         input=a.astype("<f4").tobytes(), capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<f4").astype(np.float64)


def norm(a):
    return a / (np.abs(a).max() + 1e-12)


def raw(take, end=None, af=None):
    """ElevenLabs 原始 take（raw/<take>.wav），可截到 end 秒（10 ms 淡出）再過濾鏡，峰值正規化。"""
    a = bs.decode(os.path.join(RAW, take + ".wav"))
    if end is not None:
        a = a[:int(end * SR)].copy()
        a[-441:] *= np.linspace(1, 0, 441)
    return norm(ff(a, af) if af else a)


def mix(*parts):
    """(陣列, 起點 s, 增益) 疊在一起。"""
    n = max(int(o * SR) + len(p) for p, o, _ in parts)
    out = np.zeros(n)
    for p, o, g in parts:
        out[int(o * SR):int(o * SR) + len(p)] += g * p
    return norm(out)


def t(d):
    return np.arange(int(d * SR)) / SR


def tone(f, env):
    return np.sin(2 * np.pi * np.cumsum(np.broadcast_to(f, env.shape)) / SR) * env


def noise(d):
    return rng.standard_normal(int(d * SR))


def bwop(f0=900, f1=150):
    """卡通砰：900→150 Hz 快速降音的正弦＋6 ms 低通噪音瞬態（軟木塞拔出的「啵」）。"""
    x = t(0.16)
    body = tone(f1 + (f0 - f1) * np.exp(-x / 0.018), (1 - np.exp(-x / 0.0015)) * np.exp(-x / 0.045))
    click = ff(noise(0.006) * np.exp(-t(0.006) / 0.0015), "lowpass=f=3000")
    return mix((norm(body), 0, 1), (norm(click), 0, 0.5))


def breath(d=0.45, lp=1500):
    """氣音尾巴／煙霧：200 Hz–lp 的噪音，20 ms 起、120 ms 衰減。"""
    x = t(d)
    return norm(ff(noise(d), f"highpass=f=200,lowpass=f={lp},lowpass=f={lp}") * (1 - np.exp(-x / 0.02)) * np.exp(-x / 0.12))


def boing(d=0.6):
    """彈簧 boing：200→150 Hz、11 Hz 顫動漸消的正弦＋短命的二次諧波。"""
    x = t(d)
    f = (200 - 50 * x / d) * (1 + 0.12 * np.sin(2 * np.pi * 11 * x) * np.exp(-x / 0.25))
    env = (1 - np.exp(-x / 0.003)) * np.exp(-x / 0.2)
    return norm(tone(f, env) + 0.25 * tone(2 * f, env * np.exp(-x / 0.08)))


def glide(d=0.75, f0=260, f1=1000):
    """滑哨往上拉：260→1000 Hz 指數上升、6 Hz 小顫音、越來越大聲，加一層跟著變大的氣流噪音。"""
    x = t(d)
    f = f0 * (f1 / f0) ** (x / d) * (1 + 0.02 * np.sin(2 * np.pi * 6 * x))
    env = (0.15 + 0.85 * (x / d) ** 1.5) * np.minimum(1, (d - x) / 0.015)
    whistle = ff(tone(f, env) + 0.15 * tone(2 * f, env), "lowpass=f=2500")
    air = ff(noise(d), "highpass=f=300,lowpass=f=1500") * (x / d) ** 2
    return mix((norm(whistle), 0, 1), (norm(air), 0, 0.3))


def soft_click():
    """軟喀：140 Hz 短促低音＋6 ms 低通 2.5 kHz 噪音。"""
    thump = tone(140, np.exp(-t(0.03) / 0.008))
    n = ff(noise(0.006) * np.exp(-t(0.006) / 0.0012), "lowpass=f=2500")
    return mix((norm(thump), 0, 0.7), (norm(n), 0, 0.6))


def blip(f, d=0.1):
    """圓潤 blip：正弦＋15% 二次諧波，2 ms 起音、50 ms 衰減、最後 10 ms 淡出，低通 3 kHz。"""
    x = t(d)
    env = (1 - np.exp(-x / 0.002)) * np.exp(-x / 0.05) * np.minimum(1, (d - x) / 0.01)
    return norm(ff(tone(f, env) + 0.15 * tone(2 * f, env), "lowpass=f=3000"))


POP, PACK, BTN = "VehicleCapsulePop", "VehicleCapsulePack", "VehicleCapsuleButton"
# (名稱, ID, 做法, 配方, 照提示詞與波形推測的聽感, 產生函式)
CANDIDATES = [
    (POP, "P1", "ElevenLabs＋後製", "PopChampagne_3（寫實香檳開瓶）過 SOFT 柔化",
     "低沉的軟木塞「啵」後接一段氣泡嘶嘶聲慢慢淡掉；原檔嘶聲在 9–10 kHz，已削掉大半", lambda: raw("PopChampagne_3", af=SOFT)),
    (POP, "P2", "ElevenLabs", "PopToyCork_4（卡通軟木塞 POP!），截掉尾端雜訊",
     "圓胖低沉的「啵！」，後面帶約 0.4 s 橡膠般的晃動餘音", lambda: raw("PopToyCork_4", end=0.55)),
    (POP, "P3", "ElevenLabs＋後製", "PopMagicCapsule_2（開瓶砰 → 煙霧噴出 → 亮晶晶）過 SOFT",
     "一聲「啵」之後馬上噴出一大團持續約 0.8 s 的煙霧氣流再淡出", lambda: raw("PopMagicCapsule_2", af=SOFT)),
    (POP, "P4", "ElevenLabs＋後製", "PopBubbleBloop_3（大泡泡破掉的橡膠感 bloop），截掉尾端雜訊、rubberband 放慢 15%",
     "短促、濕潤的兩段式「bl-oop」，很卡通", lambda: raw("PopBubbleBloop_3", end=0.3, af="rubberband=tempo=0.85:pitchq=quality")),
    (POP, "P5", "混音", "PopToyCork_1 的乾脆砰 ＋ 40 ms 後 PopSmokePoof_1 煙霧 poof（SOFT）",
     "清脆的「啵」緊接蓬鬆的「噗～」煙霧聲，約 0.9 s",
     lambda: mix((raw("PopToyCork_1", end=0.3), 0, 1), (raw("PopSmokePoof_1", af=SOFT), 0.04, 0.6))),
    (POP, "P6", "混音", "PopToyCork_4 卡通砰 ＋ 120 ms 後 PopSparkle_3 亮晶晶（rubberband 降一個八度、低通 3.5 kHz、-10 dB）",
     "圓胖的「啵！」之後飄出一串輕柔、偏暗的叮叮閃光",
     lambda: mix((raw("PopToyCork_4", end=0.55), 0, 1),
                 (raw("PopSparkle_3", end=0.8, af="rubberband=pitch=0.5:pitchq=quality,lowpass=f=3500,lowpass=f=3500"), 0.12, 0.32))),
    (POP, "P7", "混音", "PopBubbleBloop_3 泡泡 bloop ＋ 60 ms 後 PopSmokePoof_3 煙霧（SOFT）",
     "橡膠感「bloop」接一團柔和散開的煙",
     lambda: mix((raw("PopBubbleBloop_3", end=0.3), 0, 1), (raw("PopSmokePoof_3", af=SOFT), 0.06, 0.5))),
    (POP, "P8", "程式合成", "900→150 Hz 快速降音正弦「bwop」＋6 ms 噪音瞬態＋0.45 s 低通 1.5 kHz 氣音尾巴",
     "很乾淨的卡通「啵」，後面一口短短的「呼」", lambda: mix((bwop(), 0, 1), (breath(), 0.01, 0.3))),
    (POP, "P9", "程式合成", "同 P8 的 bwop ＋ 50 ms 後 200→150 Hz 顫動的彈簧 boing（0.6 s）",
     "「啵～嗡嗡嗡」：開瓶後像彈簧玩具彈一下", lambda: mix((bwop(), 0, 1), (boing(), 0.05, 0.55))),
    (PACK, "K1", "ElevenLabs", "PackShwoop_3（滑哨往上拉的吸入 shwoop → thoomp）",
     "從 430 Hz 平順往上滑到約 1.6 kHz 的吸入聲，持續約 1 s；結尾沒有明顯的砰", lambda: raw("PackShwoop_3")),
    (PACK, "K2", "ElevenLabs＋後製", "PackShrink_3（魔法縮小的 zip → 卡進膠囊的喀）過 SOFT、rubberband 放慢 7%",
     "快速的縮小「咻——」0.7 s，停一下，再輕輕「喀」一聲收進去",
     lambda: raw("PackShrink_3", af=SOFT + ",rubberband=tempo=0.93:pitchq=quality")),
    (PACK, "K3", "ElevenLabs＋後製", "PackGenieSwirl_4（神燈式旋轉吸入 → 塞上瓶塞的悶響），rubberband 放慢 7%",
     "旋轉的氣流被吸進瓶子，尾段約 0.9 s 一聲低悶的「咚」再淡出", lambda: raw("PackGenieSwirl_4", af="rubberband=tempo=0.93:pitchq=quality")),
    (PACK, "K4", "混音", "PackShwoop_3 吸入 ＋ 0.98 s 處接 PopToyCork_4 前 0.2 s 的低沉 thoomp",
     "滑哨往上吸到底，最後補一聲圓胖的「咚」收尾",
     lambda: mix((raw("PackShwoop_3"), 0, 1), (raw("PopToyCork_4", end=0.2), 0.98, 1.0))),
    (PACK, "K5", "混音", "PopSmokePoof_1 最濃的前 0.3 s（SOFT）用 rubberband 拉長到 1.1 s 再反轉當吸入聲 ＋ 結尾 PopToyCork_1 小砰",
     "煙霧倒著被吸回去的「呼～～」越來越大聲，最後「啵」一聲",
     lambda: mix((raw("PopSmokePoof_1", end=0.3, af=SOFT + ",rubberband=tempo=0.27:pitchq=quality,areverse,afade=t=in:d=0.1"), 0, 1),
                 (raw("PopToyCork_1", end=0.3), 1.07, 0.7))),
    (PACK, "K6", "程式合成", "260→1000 Hz 指數上升滑哨（0.75 s，帶氣流噪音）＋ 0.78 s 處 600→120 Hz 的 bwop 與氣音",
     "卡通滑哨往上拉，最後一聲低沉的「噗」", lambda: mix((glide(), 0, 1), (bwop(600, 120), 0.78, 1.0), (breath(0.3), 0.79, 0.3))),
    (BTN, "B1", "ElevenLabs＋後製", "ButtonArcade_1（街機按鈕按下放開）過 SOFT＋再低通 3 kHz",
     "兩聲間隔約 0.16 s 的「喀－嚓」，原檔偏亮（7.6 kHz），已壓暗", lambda: raw("ButtonArcade_1", af=SOFT + ",lowpass=f=3000")),
    (BTN, "B2", "ElevenLabs＋後製", "ButtonToyBeep_2（玩具按鈕喀＋確認音）用 rubberband 降兩個八度、低通 4 kHz",
     "一聲悶喀，約 0.14 s 後一聲約 1.9 kHz 的短「嗶」；原檔的嗶在 7.5 kHz 太尖才降音",
     lambda: raw("ButtonToyBeep_2", af="rubberband=pitch=0.25:pitchq=quality,lowpass=f=4000,lowpass=f=4000")),
    (BTN, "B3", "ElevenLabs＋後製", "ButtonCartoonGadget_2（卡通小工具橡膠按鈕）過 SOFT",
     "軟軟的「噗嗒」加一兩下小回彈，約 0.2 s", lambda: raw("ButtonCartoonGadget_2", af=SOFT)),
    (BTN, "B4", "程式合成", "軟喀（140 Hz 低音＋低通噪音）＋ 40 ms 後 1 kHz 圓潤 blip（0.16 s）",
     "「喀・嗶」：很乾淨的玩具按鈕確認音", lambda: mix((soft_click(), 0, 1), (blip(1000, 0.16), 0.04, 0.6))),
    (BTN, "B5", "混音＋程式合成", "B1 的街機喀－嚓 ＋ 合成兩音確認 784 Hz → 1047 Hz（G5 → C6）",
     "「喀－嚓・噗嗶」：按鈕彈回後兩音上揚的確認音",
     lambda: mix((raw("ButtonArcade_1", af=SOFT + ",lowpass=f=3000"), 0, 1), (blip(784, 0.07), 0.2, 0.45), (blip(1047), 0.28, 0.45))),
]
NOW = {  # 目前使用（build_sfx.SPEC 選定的 sfx-takes 編號）與描述
    POP: "啵 0.2 s → 短暫停頓 → 噗地冒煙升起再淡出",
    PACK: "持續的吸入咻聲 0.8 s → 停 0.2 s → 啵",
    BTN: "按下「喀」→ 0.2 s 後彈回「嚓」",
}
TITLES = {POP: "丟出膠囊、彈開出車（VehicleCapsulePop）", PACK: "把車收進膠囊（VehicleCapsulePack）",
          BTN: "按膠囊按鈕（VehicleCapsuleButton）"}


def save(name, cid, a):
    """照 build_sfx 的整理法寫成 44.1 kHz 單聲道 16-bit wav，回傳成品的 stats。"""
    dst = os.path.join(V2, f"{name}_{cid}.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
                    "-af", bs.level_af(bs.stats(a)), "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le",
                    "-map_metadata", "-1", dst], input=a.astype("<f4").tobytes(), check=True)
    s = bs.stats(bs.decode(dst))
    bad = bs.check(name, s)
    print(f"{name}_{cid}: active {s['active']:.2f}s centroid {s['centroid']:.0f} Hz  {'OK' if not bad else 'NG: ' + '；'.join(bad)}")
    return s


def page(rows):
    e = html.escape
    out = ["<!doctype html><html lang='zh-Hant'><meta charset='utf-8'><title>車輛膠囊音效候選 v2</title>",
           "<style>body{font-family:system-ui,'Microsoft JhengHei',sans-serif;max-width:1100px;margin:2em auto;padding:0 1em;"
           "line-height:1.5}table{border-collapse:collapse;width:100%;margin-bottom:2em}td,th{border:1px solid #ccc;"
           "padding:.4em .6em;vertical-align:top;text-align:left}th{background:#f4f4f4}tr.now{background:#fff8e0}"
           "audio{width:260px}.id{font-weight:bold;white-space:nowrap}small{color:#666}</style>",
           "<h1>車輛膠囊音效候選（第 2 版）</h1>",
           "<p>所有候選都對齊響度（剪掉前面靜音、RMS 峰值 -18 dBFS、限幅 -1 dBFS），可以直接比較。"
           "「聽起來像」一欄<strong>沒有人耳試聽過</strong>，是照提示詞與波形（包絡、頻譜）推測的。"
           "選好後：<code>uv run scripts/assets/build_sfx.py --write --pick VehicleCapsulePop=v2:P3</code>（換成你選的 ID）。</p>"]
    for name in (POP, PACK, BTN):
        out.append(f"<h2>{e(TITLES[name])}</h2><table><tr><th>ID</th><th>試聽</th><th>做法</th><th>配方</th>"
                   "<th>聽起來像（推測）</th><th>有聲長度</th><th>頻譜重心</th></tr>")
        for n, cid, how, recipe, guess, s in rows:
            if n != name:
                continue
            f = f"{name}_{cid}.wav"
            out.append(f"<tr class='{'now' if cid == 'now' else ''}'><td class='id'>{'目前使用' if cid == 'now' else cid}</td>"
                       f"<td><audio controls preload='auto' src='{e(f)}'></audio></td><td>{e(how)}</td><td>{e(recipe)}</td>"
                       f"<td>{e(guess)}</td><td>{s['active']:.2f} s</td><td>{s['centroid'] / 1000:.1f} kHz</td></tr>")
        out.append("</table>")
    return "\n".join(out) + "\n"


def main():
    rows = []
    for name, (_, take) in bs.SPEC.items():
        s = save(name, "now", bs.decode(bs.src_path(name, take)))
        rows.append((name, "now", "ElevenLabs（第 1 版）", f"sfx-takes/{name}_{take}.wav", NOW[name], s))
    for name, cid, how, recipe, guess, make in CANDIDATES:
        rows.append((name, cid, how, recipe, guess, save(name, cid, make())))
    with open(os.path.join(V2, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(page(rows))
    print("->", os.path.relpath(os.path.join(V2, "index.html"), bs.REPO))


if __name__ == "__main__":
    main()
