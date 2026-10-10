# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""車輛膠囊音效第 2、3 版候選：從 ElevenLabs 原始 take 加程式合成元素，重建所有候選與試聽頁。

步驟（repo 根目錄）：
    python ~/.omp/agent/skills/elevenlabs-tts/scripts/eleven_tts.py sfx --manifest scripts/assets/sfx_v2.json \
        --out-dir temp/assets-review/sfx-v2/raw --format wav --variants 4 --trim
    python ~/.omp/agent/skills/elevenlabs-tts/scripts/eleven_tts.py sfx --manifest scripts/assets/sfx_v3.json \
        --out-dir temp/assets-review/sfx-v3/raw --format wav --variants 4 --trim
    uv run scripts/assets/design_sfx.py       # 寫 temp/assets-review/sfx-v2、sfx-v3 的 <Name>_<ID>.wav 與 index.html
    uv run scripts/assets/build_sfx.py        # 列表模式檢查長度；選定後 --write --pick <Name>=v3:<ID>

第 2 版：Pop／Pack／Button 各一組（Pack 已選 K3）。第 3 版（使用者：丟出＋彈開要更誇大的卡通化，丟出「咻～」、落地「蹦！」）：
新的 VehicleCapsuleThrow（膠囊固定飛 500 ms）、更誇張的 Pop P10 起，以及「咻在 0 s、蹦在 0.5 s」的組合 Combo_C<n>.wav。
每條候選都照 build_sfx.level_af 整理（剪前面靜音、淡入淡出、RMS 峰值 -18 dBFS、限幅 -1 dBFS），試聽才公平。
ElevenLabs 的 take 高頻偏多（開瓶嘶聲、按鈕喀聲、zip 重心 5–10 kHz），SOFT 照 elevenlabs-tts 技能的刺耳處理削掉。
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
REVIEW = bs.REVIEW
RAWS = [os.path.join(REVIEW, f"sfx-{v}", "raw") for v in ("v2", "v3")]
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
    """ElevenLabs 原始 take（sfx-v2/raw 或 sfx-v3/raw 的 <take>.wav），可截到 end 秒（10 ms 淡出）再過濾鏡，峰值正規化。"""
    a = bs.decode(next(p for p in (os.path.join(r, take + ".wav") for r in RAWS) if os.path.exists(p)))
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


def svf_bandpass(x, fc, q):
    """時變帶通（Chamberlin state-variable filter），fc 是逐樣本的中心頻率陣列。"""
    g = 2 * np.sin(np.pi * np.minimum(fc, 8000) / SR)
    low = band = 0.0
    out = np.empty_like(x)
    for i in range(len(x)):
        low += g[i] * band
        band += g[i] * (x[i] - low - band / q)
        out[i] = band
    return out


def arc(x, d, peak):
    """0 → 1（在 peak 秒）→ 0 的三角包絡，拿來排拋物線的音高與掃頻。"""
    return np.where(x < peak, x / peak, 1 - (x - peak) / (d - peak))


def whistle_arc(d=0.55, f0=450, fmax=1000, f1=500, peak=0.4):
    """滑哨「咻嗚～」：450 Hz 往上滑到 1 kHz（前 40%）再落到 500 Hz、7 Hz 小顫音，低通 2.5 kHz；
    加一層中心跟著 1.5 倍音高走的帶通氣流噪音。"""
    x = t(d)
    p = arc(x, d, d * peak)
    f = np.where(x < d * peak, f0 + (fmax - f0) * np.sin(np.pi / 2 * p), f1 + (fmax - f1) * p) * (1 + 0.015 * np.sin(2 * np.pi * 7 * x))
    env = np.minimum(1, x / 0.04) * np.minimum(1, (d - x) / 0.12)
    whistle = ff(tone(f, env) + 0.2 * tone(2 * f, env), "lowpass=f=2500")
    air = svf_bandpass(noise(d), 1.5 * f, 3) * env
    return mix((norm(whistle), 0, 1), (norm(air), 0, 0.35))


def swish(d=0.6, peak=0.3):
    """都卜勒式 swish：白噪音過帶通，中心 500 → 2000 Hz（peak 秒）→ 500 Hz，再兩次低通 2.5 kHz（帶通裙邊留下的白噪音高頻很刺），
    音量在 peak 最大；底下墊 150–500 Hz 的低氣流。"""
    x = t(d)
    env = np.exp(-((x - peak) / 0.16) ** 2)
    hiss = ff(svf_bandpass(noise(d), 500 + 1500 * arc(x, d, peak) ** 1.5, 2.5), "lowpass=f=2500,lowpass=f=2500") * env
    low = ff(noise(d), "highpass=f=150,lowpass=f=500") * env
    return mix((norm(hiss), 0, 1), (norm(low), 0, 0.4))


def bonk(f0=360, f1=100, d=0.18):
    """橡膠球落地的「咚」：f0 → f1 快速降音（τ 20 ms）的正弦、50 ms 衰減，加 4 ms 低通噪音瞬態。"""
    x = t(d)
    body = tone(f1 + (f0 - f1) * np.exp(-x / 0.02), (1 - np.exp(-x / 0.001)) * np.exp(-x / 0.05))
    click = ff(noise(0.004) * np.exp(-t(0.004) / 0.001), "lowpass=f=3000")
    return mix((norm(body), 0, 1), (norm(click), 0, 0.4))


def kaboing(d=0.75):
    """卡通 kaboing：160 → 50 Hz 的重低音砰＋20 ms 噪音爆裂（200 Hz–4 kHz）＋口簧琴式 twang
    （140 Hz 起、前 40 ms 往下掉 30%、13 Hz 大幅顫動漸消；1–6 次諧波 1/n，低通 1.8 kHz）。"""
    x = t(d)
    thump = tone(50 + 110 * np.exp(-t(0.25) / 0.03), np.exp(-t(0.25) / 0.1))
    burst = ff(noise(0.02) * np.exp(-t(0.02) / 0.005), "highpass=f=200,lowpass=f=4000")
    f = 140 * (1 + 0.3 * np.exp(-x / 0.04)) * (1 + 0.18 * np.sin(2 * np.pi * 13 * x) * np.exp(-x / 0.3))
    env = (1 - np.exp(-x / 0.002)) * np.exp(-x / 0.22)
    twang = ff(sum(tone(n * f, env) / n for n in range(1, 7)), "lowpass=f=1800,lowpass=f=1800")
    return mix((norm(thump), 0, 1), (norm(burst), 0, 0.6), (norm(twang), 0.015, 0.8))


POP, PACK, BTN, THROW = "VehicleCapsulePop", "VehicleCapsulePack", "VehicleCapsuleButton", "VehicleCapsuleThrow"
# 第 2 版：(名稱, ID, 做法, 配方, 照提示詞與波形推測的聽感, 產生函式)，寫進 sfx-v2
V2_CANDIDATES = [
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
# 第 3 版：同上格式，寫進 sfx-v3。Throw 的有聲長度抓 0.45–0.6 s 配合 500 ms 飛行。
V3_CANDIDATES = [
    (THROW, "T1", "ElevenLabs", "ThrowSlideWhistle_1（卡通滑哨），截在 0.6 s",
     "滑哨從約 1.4 kHz 一路往下滑到 0.5 kHz 的「咻～嗚」，像膠囊劃一道弧落下", lambda: raw("ThrowSlideWhistle_1", end=0.6)),
    (THROW, "T2", "ElevenLabs", "ThrowSlideWhistle_3（卡通滑哨），截在 0.6 s",
     "滑哨先落、再往上揚、最後落下的「咻～咿～嗚」，起伏比 T1 多", lambda: raw("ThrowSlideWhistle_3", end=0.6)),
    (THROW, "T3", "ElevenLabs", "ThrowSpin_1（卡通旋轉膠囊被丟出）",
     "一陣帶顫動的「咻嚕嚕」旋轉氣流，像玩具邊轉邊飛", lambda: raw("ThrowSpin_1")),
    (THROW, "T4", "ElevenLabs＋後製", "ThrowWhoosh_2（卡通丟擲 whoosh），rubberband 放慢 20% 拉到約 0.5 s",
     "一口「咻——」的風聲，起頭最大、音高往下掉再淡出", lambda: raw("ThrowWhoosh_2", af="rubberband=tempo=0.8:pitchq=quality")),
    (THROW, "T5", "ElevenLabs＋後製", "ThrowDoppler_3（都卜勒飛過的 swish），過 SOFT、rubberband 放慢 30%",
     "由小變大再變小的「咻～」氣流，像東西從身邊飛過",
     lambda: raw("ThrowDoppler_3", af=SOFT + ",rubberband=tempo=0.7:pitchq=quality")),
    (THROW, "T6", "ElevenLabs＋後製", "ThrowZip_2（卡通 zip）用 rubberband 降一個八度、放慢 25%，兩次 4 kHz 低通；原檔重心 5.3 kHz 太尖",
     "降音後變成較圓的橡膠感「啾溜～」快速飛走",
     lambda: raw("ThrowZip_2", af="rubberband=tempo=0.75:pitch=0.5:pitchq=quality,lowpass=f=4000,lowpass=f=4000")),
    (THROW, "T7", "程式合成", "滑哨 450 Hz → 1 kHz（前 40%）→ 500 Hz、7 Hz 顫音、低通 2.5 kHz，加跟著音高走的帶通氣流噪音，0.55 s",
     "很乾淨的卡通滑哨「咻～嗚」，畫一道拋物線", lambda: whistle_arc()),
    (THROW, "T8", "程式合成", "白噪音過時變帶通，中心 500 → 2000 Hz（0.3 s）→ 500 Hz，兩次低通 2.5 kHz，音量在 0.3 s 最大；墊 150–500 Hz 低氣流，0.6 s",
     "純氣流的「咻～」，由遠而近再遠去（都卜勒感），沒有音高", lambda: swish()),
    (POP, "P10", "ElevenLabs", "PopBoing（誇張卡通落地 BOING）take 1",
     "大顆、低沉（150–330 Hz）的「蹦～嗡」，彈簧晃動約 0.4 s", lambda: raw("PopBoing_1")),
    (POP, "P11", "ElevenLabs＋後製", "PopKaboing（卡通爆開＋彈簧 twang）take 1 過 SOFT；原檔重心 4.6 kHz",
     "一聲爆開的「砰」立刻接往上揚的「嗡～」twang（725 Hz → 2 kHz）", lambda: raw("PopKaboing_1", af=SOFT)),
    (POP, "P12", "ElevenLabs", "PopRubberTwang（深沉橡皮筋 twang）take 2，截在 0.6 s 去掉尾端雜訊",
     "低沉的橡膠「彈～嗡嗡」，100 Hz 上下晃動、瞬態 5 次", lambda: raw("PopRubberTwang_2", end=0.6)),
    (POP, "P13", "ElevenLabs", "PopBounceBall（卡通彈力球）take 4",
     "「咚！」落地，0.24 s 後再彈一下「咚」，最後小小的餘彈", lambda: raw("PopBounceBall_4")),
    (POP, "P14", "ElevenLabs", "PopGiant（巨大卡通 POP!＋煙霧）take 3，截在 0.7 s",
     "很飽滿的「砰！」接一團低沉的「噗～」煙霧散開", lambda: raw("PopGiant_3", end=0.7)),
    (POP, "P15", "混音", "PopGiant_4 的前 0.12 s（大砰）＋ 30 ms 後 PopBoing_1 的彈簧 boing（×0.8）",
     "「砰—蹦嗡～」：先一聲大砰，再接彈簧晃動",
     lambda: mix((raw("PopGiant_4", end=0.12), 0, 1), (raw("PopBoing_1"), 0.03, 0.8))),
    (POP, "P16", "混音", "PopBounceBall_4 彈力球 ＋ 50 ms 後 PopSmokePoof_1 煙霧（SOFT，×0.45）",
     "「咚！咚」彈兩下，同時噴出一團「噗～」煙霧",
     lambda: mix((raw("PopBounceBall_4"), 0, 1), (raw("PopSmokePoof_1", af=SOFT), 0.05, 0.45))),
    (POP, "P17", "程式合成", "kaboing：160 → 50 Hz 重低音砰＋20 ms 噪音爆裂＋口簧琴式 twang（140 Hz、13 Hz 大幅顫動、1–6 次諧波、低通 1.8 kHz）",
     "「砰～嗡嗡嗡」：大顆的爆開接彈簧晃動，最誇張的一條", lambda: kaboing()),
    (POP, "P18", "程式合成", "四下橡膠球「咚」：360→100 Hz 降音正弦，間隔 0.22／0.14／0.09 s 越彈越快，音量 1／0.55／0.3／0.15、音高越來越高",
     "「咚！咚、咚咚」：膠囊落地彈跳幾下停住",
     lambda: mix((bonk(360, 100), 0, 1), (bonk(420, 120), 0.22, 0.55), (bonk(480, 140), 0.36, 0.3), (bonk(520, 160), 0.45, 0.15))),
]
# 組合試聽：(ID, 咻, 蹦, 推測)。咻從 0 s、蹦從 0.5 s（膠囊固定飛 500 ms）開始，只供試聽；裝進 MOD 時分別選 T 與 P。
COMBOS = [
    ("C1", "v3:T1", "v3:P13", "滑哨往下劃弧，落地「咚！咚」彈兩下"),
    ("C2", "v3:T3", "v3:P11", "旋轉飛出的「咻嚕嚕」，落地爆開「砰～嗡」"),
    ("C3", "v3:T7", "v3:P17", "全合成：滑哨拋物線接最誇張的 kaboing"),
    ("C4", "v3:T4", "v3:P14", "一口風聲「咻——」，落地大「砰！」冒煙"),
    ("C5", "v3:T8", "v3:P15", "氣流由遠而近「咻～」，落地「砰—蹦嗡～」"),
]
V2_NOW = {  # 第 2 版頁上的「目前使用」：當時 build_sfx.SPEC 選定的 sfx-takes 編號與描述
    POP: (12, "啵 0.2 s → 短暫停頓 → 噗地冒煙升起再淡出"),
    PACK: (7, "持續的吸入咻聲 0.8 s → 停 0.2 s → 啵"),
    BTN: (4, "按下「喀」→ 0.2 s 後彈回「嚓」"),
}
TITLES = {THROW: "丟出膠囊的咻聲（VehicleCapsuleThrow，新）", POP: "丟出膠囊、彈開出車（VehicleCapsulePop）",
          PACK: "把車收進膠囊（VehicleCapsulePack）", BTN: "按膠囊按鈕（VehicleCapsuleButton）"}
NOTE = ("所有候選都對齊響度（剪掉前面靜音、RMS 峰值 -18 dBFS、限幅 -1 dBFS），可以直接比較。"
        "「聽起來像」一欄<strong>沒有人耳試聽過</strong>，是照提示詞與波形（包絡、頻譜）推測的。")


def save(ver, name, cid, a):
    """照 build_sfx 的整理法寫成 sfx-<ver>/<name>_<cid>.wav（44.1 kHz 單聲道 16-bit），回傳成品的 stats。"""
    dst = os.path.join(REVIEW, f"sfx-{ver}", f"{name}_{cid}.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
                    "-af", bs.level_af(bs.stats(a)), "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le",
                    "-map_metadata", "-1", dst], input=a.astype("<f4").tobytes(), check=True)
    s = bs.stats(bs.decode(dst))
    bad = bs.check(name, s) if name in bs.SPEC else []
    print(f"{ver}:{name}_{cid}: active {s['active']:.2f}s centroid {s['centroid']:.0f} Hz  {'OK' if not bad else 'NG: ' + '；'.join(bad)}")
    return s


def row(label, src, how, recipe, guess, s, cls=""):
    return {"label": label, "src": src, "how": how, "recipe": recipe, "guess": guess, "s": s, "cls": cls}


def page(ver, title, intro, sections):
    """sections：[(小標, [row…])]；audio 用相對路徑，瀏覽器直接開檔就能播。"""
    e = html.escape
    out = [f"<!doctype html><html lang='zh-Hant'><meta charset='utf-8'><title>{e(title)}</title>",
           "<style>body{font-family:system-ui,'Microsoft JhengHei',sans-serif;max-width:1100px;margin:2em auto;padding:0 1em;"
           "line-height:1.5}table{border-collapse:collapse;width:100%;margin-bottom:2em}td,th{border:1px solid #ccc;"
           "padding:.4em .6em;vertical-align:top;text-align:left}th{background:#f4f4f4}tr.now{background:#fff8e0}"
           "tr.ref{color:#666}audio{width:260px}.id{font-weight:bold;white-space:nowrap}</style>",
           f"<h1>{e(title)}</h1>", f"<p>{intro}</p>"]
    for head, rows in sections:
        out.append(f"<h2>{e(head)}</h2><table><tr><th>ID</th><th>試聽</th><th>做法</th><th>配方</th>"
                   "<th>聽起來像（推測）</th><th>有聲長度</th><th>頻譜重心</th></tr>")
        for r in rows:
            out.append(f"<tr class='{r['cls']}'><td class='id'>{e(r['label'])}</td>"
                       f"<td><audio controls preload='auto' src='{e(r['src'])}'></audio></td><td>{e(r['how'])}</td>"
                       f"<td>{e(r['recipe'])}</td><td>{e(r['guess'])}</td><td>{r['s']['active']:.2f} s</td>"
                       f"<td>{r['s']['centroid'] / 1000:.1f} kHz</td></tr>")
        out.append("</table>")
    dst = os.path.join(REVIEW, f"sfx-{ver}", "index.html")
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("->", os.path.relpath(dst, bs.REPO))


def build_v2():
    rows = {POP: [], PACK: [], BTN: []}
    for name, (take, guess) in V2_NOW.items():
        s = save("v2", name, "now", bs.decode(bs.src_path(name, take)))
        rows[name].append(row("目前使用", f"{name}_now.wav", "ElevenLabs（第 1 版）", f"sfx-takes/{name}_{take}.wav", guess, s, "now"))
    for name, cid, how, recipe, guess, make in V2_CANDIDATES:
        rows[name].append(row(cid, f"{name}_{cid}.wav", how, recipe, guess, save("v2", name, cid, make())))
    page("v2", "車輛膠囊音效候選（第 2 版）",
         NOTE + "選好後：<code>uv run scripts/assets/build_sfx.py --write --pick VehicleCapsulePop=v2:P3</code>（換成你選的 ID）。",
         [(TITLES[n], rows[n]) for n in (POP, PACK, BTN)])
    return rows


def build_v3(v2rows):
    def ref(r, label=None, cls="ref"):
        return {**r, "src": "../sfx-v2/" + r["src"], "label": label or f"{r['label']}（第 2 版）", "cls": cls}

    v2 = {(n, r["label"]): r for n, rs in v2rows.items() for r in rs}
    rows = {THROW: [], POP: [ref(v2[POP, "目前使用"], "目前使用", "now")]}
    for name, cid, how, recipe, guess, make in V3_CANDIDATES:
        rows[name].append(row(cid, f"{name}_{cid}.wav", how, recipe, guess, save("v3", name, cid, make())))
    rows[POP] += [ref(r) for r in v2rows[POP][1:]]
    combos = []
    for cid, throw, pop, guess in COMBOS:
        a, p = bs.decode(bs.src_path(THROW, throw)), bs.decode(bs.src_path(POP, pop))
        out = np.zeros(max(len(a), int(0.5 * SR) + len(p)))
        out[:len(a)] += a
        out[int(0.5 * SR):int(0.5 * SR) + len(p)] += p
        combos.append(row(cid, f"Combo_{cid}.wav", "組合", f"{throw[3:]} 咻（0 s）＋ {pop[3:]} 蹦（0.5 s）", guess,
                          save("v3", "Combo", cid, out)))
    page("v3", "車輛膠囊音效候選（第 3 版）",
         NOTE + "組合只供試聽整個丟出的感覺（咻從 0 s、蹦從 0.5 s 開始）；裝進 MOD 時分別選咻（T）與蹦（P）："
         "<code>uv run scripts/assets/build_sfx.py --write --pick VehicleCapsuleThrow=v3:T1 VehicleCapsulePop=v3:P13</code>"
         "（換成你選的 ID；第 2 版的 P1–P9 用 <code>v2:P3</code> 這種寫法）。",
         [("丟出＋彈開組合（咻 0 s → 蹦 0.5 s）", combos), (TITLES[THROW], rows[THROW]), (TITLES[POP], rows[POP]),
          (TITLES[PACK], [ref(v2[PACK, "K3"], "已選 K3", "now"), ref(v2[PACK, "目前使用"], "舊版（第 1 版 take 7）")]),
          (TITLES[BTN], [ref(v2[BTN, "目前使用"], "已選（目前 take 4）", "now")])])


def main():
    build_v3(build_v2())


if __name__ == "__main__":
    main()
