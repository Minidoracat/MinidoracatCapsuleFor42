# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""萬用膠囊音效：檢查 ElevenLabs 產生的候選檔，挑定的那一條做響度整理後轉成 MOD 用的 .ogg。

步驟（repo 根目錄；生成器見 skill elevenlabs-tts，提示詞在 scripts/assets/sfx.json）：
    python ~/.omp/agent/skills/elevenlabs-tts/scripts/eleven_tts.py sfx --manifest scripts/assets/sfx.json \
        --out-dir temp/assets-review/sfx-takes --format wav --variants 4
    uv run scripts/assets/build_sfx.py              # 只列每條候選的長度、峰值、RMS、起音、尾巴、頻譜重心
    uv run scripts/assets/build_sfx.py --write      # 用 SPEC 選定的候選寫進 MOD 的 media/sound/MinidoracatCapsule/

第 2–4 版候選（提示詞 scripts/assets/sfx_v2.json–sfx_v4.json，混音與合成 scripts/assets/design_sfx.py，試聽頁
temp/assets-review/sfx-v<N>/index.html）用 `v<N>:<ID>` 指定 temp/assets-review/sfx-v<N>/<Name>_<ID>.wav，例如：
    uv run scripts/assets/build_sfx.py --write --pick UniversalCapsulePop=v4:P19
第 5 版（效果樣式，提示詞 scripts/assets/sfx_v5.json，演示頁 scripts/assets/design_fx.py）、第 6 版（七種款式補錄的 5 段，
scripts/assets/sfx_v6.json）與第 7 版（衝擊款的爆炸聲，scripts/assets/sfx_v7.json；試聽挑選頁都是 scripts/assets/pick_sfx.py）
沒有 <Name>_<ID>.wav，`v<N>:<ID>` 直接讀 ElevenLabs 原始 take temp/assets-review/sfx-v<N>/raw/<ID>.wav。只寫某幾條：--write 後面接名稱。
整理：先剪掉 CUT 指定的開頭（主聲比畫面晚到的 take），4 ms 淡入、60 ms 淡出，增益調到 RMS 峰值（50 ms 窗）TARGET_RMS_DB
（-18 dBFS；出車的 UniversalCapsulePop* 用 LOUDER_DB），
再 alimiter 限在 -1 dBFS；44.1 kHz 單聲道 Vorbis q5。sound script 在 media/scripts/MinidoracatCapsule_sounds.txt。
"""
import argparse
import os
import subprocess
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TAKES = os.path.join(REPO, "temp", "assets-review", "sfx-takes")
REVIEW = os.path.join(REPO, "temp", "assets-review")
OUT = os.path.join(REPO, "MOD", "MinidoracatCapsuleFor42", "Contents", "mods", "MinidoracatCapsuleFor42",
                   "42", "media", "sound", "MinidoracatCapsule")
SR = 44100
# 名稱 → (可接受的有聲長度範圍 s, 選定的候選)。候選：sfx-takes 的編號，或 "v<N>:<ID>"；None = 還沒選，--write 時略過。
# 規格：Throw 0.3–0.8 s（膠囊固定飛 500 ms）、Pop 0.25–1.6 s（開瓶砰聲較短）、Pack 約 1.0–1.5 s、Button 約 0.3 s。
# 2026-10-10 選定（沒人耳試聽，依波形輪廓挑；用 `uv run scripts/assets/build_sfx.py` 看 env dB）：
#   Pop v4:P23：使用者試聽第 4 輪「T1＋蹦」組合後選定（ElevenLabs 拉炮式的碰，過 SOFT，尾巴短，0.5 s，-14 dBFS）。
#     前幾輪：take 12（啵 → 停頓 → 噗地冒煙，0.81 s）、開瓶砰聲 P1–P9、誇張卡通 P10–P18 都沒選。
#   Pack 7：持續的吸入咻聲 0.8 s → 停 0.2 s → 啵，有聲 1.07 s，頻譜重心 2.1 kHz（不刺耳）。
#     第 3 輪使用者試聽後改選 v2:K3（神燈式旋轉吸入 → 塞上瓶塞的悶響）。
#   Button 4：按下「喀」→ 0.2 s 後彈回「嚓」，有聲 0.26 s；第 3 輪使用者試聽後維持。
#   Throw v3:T1：使用者試聽第 3 輪後選定（ElevenLabs 滑哨咻聲，約 1.4 kHz 往下劃到 0.5 kHz，0.59 s）；膠囊固定飛 500 ms，
#     所以一條聲音配所有距離。
SPEC = {
    "UniversalCapsuleThrow": ((0.3, 0.8), "v3:T1"),
    "UniversalCapsulePop": ((0.25, 1.6), "v4:P23"),
    "UniversalCapsulePack": ((1.0, 1.5), "v2:K3"),
    "UniversalCapsuleButton": ((0.15, 0.5), 4),
}
# 卡通以外的六種款式（shared/Core.lua 的 M.TYPES 列出每種用哪四條）。名稱＝UniversalCapsule＋提示詞 id。
# 2026-10-12 使用者在試聽頁（scripts/assets/pick_sfx.py，配特效動畫）挑了兩輪：17 段維持原本的預設（同一句提示詞裡長度合格、
# 頻譜重心最低的 take），換了 6 段（PackReal_3、PackSteam_4、PopSci_3、ThrowMagic_1、ButtonMagic_4、PackShock_4）；
# 衝擊款的彈開改成爆炸聲（下面第 7 版）。
THROW, POP, PACK, BUTTON = (0.25, 0.9), (0.3, 1.7), (0.4, 1.6), (0.06, 0.7)
SPEC.update({
    "UniversalCapsuleThrowReal": (THROW, "v5:ThrowReal_3"),
    "UniversalCapsuleThrowReal2": (THROW, "v5:ThrowReal2_4"),
    "UniversalCapsuleThrowSci": (THROW, "v5:ThrowSci_3"),
    "UniversalCapsuleThrowMagic": (THROW, "v5:ThrowMagic_1"),
    "UniversalCapsulePopReal": (POP, "v5:PopReal_4"),
    "UniversalCapsulePopHeavyDrop": (POP, "v5:PopHeavyDrop_4"),
    "UniversalCapsulePopSteam": (POP, "v5:PopSteam_1"),
    "UniversalCapsulePopSci": (POP, "v5:PopSci_3"),
    "UniversalCapsulePopMagic": (POP, "v5:PopMagic_1"),
    "UniversalCapsulePackReal": (PACK, "v5:PackReal_3"),
    "UniversalCapsulePackHeavy": (PACK, "v5:PackHeavy_1"),
    "UniversalCapsulePackSteam": (PACK, "v5:PackSteam_4"),
    "UniversalCapsulePackSci": (PACK, "v5:PackSci_4"),
    "UniversalCapsulePackMagic": (PACK, "v5:PackMagic_2"),
    "UniversalCapsuleButtonReal": (BUTTON, "v5:ButtonReal_3"),
    "UniversalCapsuleButtonSwitch": (BUTTON, "v5:ButtonSwitch_2"),
    "UniversalCapsuleButtonSci": (BUTTON, "v5:ButtonSci_3"),
    "UniversalCapsuleButtonMagic": (BUTTON, "v5:ButtonMagic_4"),
})
# 七種款式（設計稿 vcap-types-1012）原本借用別款的 5 段新錄：提示詞 scripts/assets/sfx_v6.json，`v6:<ID>` 讀 sfx-v6/raw。
SPEC.update({
    "UniversalCapsuleThrowSteam": (THROW, "v6:ThrowSteam_1"),
    "UniversalCapsuleThrowShock": (THROW, "v6:ThrowShock_3"),
    "UniversalCapsulePackShock": (PACK, "v6:PackShock_4"),
    "UniversalCapsuleButtonDust": (BUTTON, "v6:ButtonDust_1"),
    "UniversalCapsuleButtonShock": (BUTTON, "v6:ButtonShock_3"),
})
# 衝擊款的彈開換成爆炸聲（使用者 2026-10-12：「應該換大一點的爆炸聲」）：第 7 版提示詞 scripts/assets/sfx_v7.json，三種爆炸各
# 4 條（`v7:<ID>` 讀 sfx-v7/raw），提示詞要求一開頭就炸，12 條主聲都在開頭 20 ms 內。使用者在試聽頁挑定 PopMushroom_4
# （蘑菇雲火球：低沉轟隆加火焰劈啪，1.6 s）。
SPEC.update({"UniversalCapsulePopExplosion": (POP, "v7:PopMushroom_4")})
# 主聲比畫面晚的 take（使用者在試聽頁配特效聽出來）：剪掉原始 take 開頭這幾秒，主瞬態就落在觸發那一刻（出車、收車）。
#   PopReal_4：前 0.39 s 是細的高頻嘶聲，砰在後面；PackShock_4：嗡聲蓄能 0.71 s 才炸開（3 kHz 以上的瞬態起點）。
CUT = {"v5:PopReal_4": 0.385, "v6:PackShock_4": 0.705}
# 先過 SOFT 再整理響度：原檔頻譜重心超過 4 kHz、而且是容易刺耳的音色（閃光、電子音；design_fx.py、pick_sfx.py 同一條規則）
SOFTEN = {"UniversalCapsuleThrowSci", "UniversalCapsuleThrowMagic", "UniversalCapsulePackMagic", "UniversalCapsuleButtonShock"}
SOFT = "highpass=f=80,equalizer=f=3000:t=o:w=1.5:g=-5,equalizer=f=6500:t=o:w=1:g=-4,lowpass=f=5000,lowpass=f=5000"
TARGET_RMS_DB = -18.0
# 第 4 輪使用者：「蹦的聲音可以大一點，要有炸開的感覺」，出車的蹦聲（每個效果樣式的 UniversalCapsulePop*）提高 4 dB。
LOUDER_DB = -14.0


def target_db(name):
    return LOUDER_DB if name.startswith("UniversalCapsulePop") else TARGET_RMS_DB


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "pipe:1"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0


def stats(a):
    env = np.abs(a)
    peak = env.max()
    win = int(0.05 * SR)
    rms_win = np.sqrt(np.convolve(a * a, np.ones(win) / win, mode="same"))
    loud = int(np.argmax(rms_win))
    seg = a[max(0, loud - 2048):loud + 2048]
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
    fr = np.fft.rfftfreq(len(seg), 1 / SR)
    short = np.sqrt(np.convolve(a * a, np.ones(441) / 441, mode="same"))   # 10 ms RMS
    hits, last = 0, -SR
    for i in np.flatnonzero((short[1:-1] > short[:-2]) & (short[1:-1] >= short[2:]) & (short[1:-1] > short.max() * 0.25)):
        if (i - last) / SR >= 0.06:
            hits, last = hits + 1, i
    onset = np.argmax(env > peak * 0.1) / SR                                # 第一次超過峰值 -20 dB
    tail = (len(a) - np.argmax(env[::-1] > peak * 0.01)) / SR               # 最後一次超過峰值 -40 dB
    return {
        "dur": len(a) / SR,
        "peak_db": 20 * np.log10(peak + 1e-12),
        "rms_peak_db": 20 * np.log10(rms_win.max() + 1e-12),
        "onset": onset,
        "tail": tail,
        "active": tail - onset,
        "hits": hits,                                                       # 相隔 >=60 ms、在峰值 -12 dB 內的瞬態數
        # 波形輪廓：有聲段切 12 格，每格 RMS 相對整條 RMS 峰值的 dB（看「先砰後噗」「先吸後啵」的形狀）
        "env": [round(20 * np.log10(np.sqrt(np.mean(c * c)) / (rms_win.max() + 1e-12) + 1e-9))
                for c in np.array_split(a[int(onset * SR):int(tail * SR)], 12) if c.size],
        "loudest": loud / SR,
        "centroid": float((sp * fr).sum() / (sp.sum() + 1e-12)),
        "clipped": int((env > 0.999).sum()),
    }


def check(name, s):
    (lo, hi), _ = SPEC[name]
    bad = []
    if not lo <= s["active"] <= hi:
        bad.append(f"有聲長度 {s['active']:.2f}s 不在 {lo}-{hi}")
    if s["peak_db"] < -20:
        bad.append("太小聲")
    if s["clipped"] > 10:
        bad.append(f"削波 {s['clipped']} 點")
    return bad


def src_path(name, take):
    """take：sfx-takes 的編號，或 `v<N>:<ID>` 指 sfx-v<N>/<name>_<ID>.wav（第 5 版：sfx-v5/raw/<ID>.wav）。"""
    take = str(take)
    if take.startswith("v") and ":" in take:
        ver, cid = take.split(":", 1)
        own = os.path.join(REVIEW, f"sfx-{ver}", f"{name}_{cid}.wav")
        return own if os.path.exists(own) else os.path.join(REVIEW, f"sfx-{ver}", "raw", f"{cid}.wav")
    return os.path.join(TAKES, f"{name}_{take}.wav")


def level_af(s, target=TARGET_RMS_DB):
    """stats → ffmpeg 濾鏡：剪掉前面的靜音（觸發就出聲）、淡入淡出、增益到 target（RMS 峰值 dBFS）、限幅 -1 dBFS。"""
    start = max(0.0, s["onset"] - 0.005)
    end = s["tail"] + 0.06
    return (f"atrim={start:.3f}:{end:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.004,"
            f"afade=t=out:st={end - start - 0.06:.3f}:d=0.06,"
            f"volume={target - s['rms_peak_db']:.2f}dB,alimiter=limit=0.891:level=0")


def soften(a):
    """SOFT 濾鏡（削 3 kHz 以上的刺耳頻段，elevenlabs-tts 技能 2026-10-06 的做法）；32-bit float 進出，中途不削波。"""
    out = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
                          "-af", SOFT, "-f", "f32le", "pipe:1"], input=a.astype("<f4").tobytes(),
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<f4").astype(np.float64)


def load(name, take):
    """原始 take → 浮點波形，先剪掉 CUT 的開頭。write 與試聽頁（pick_sfx.py）都從這裡讀，聽到的就是裝進 MOD 的。"""
    return decode(src_path(name, take))[int(CUT.get(str(take), 0.0) * SR):]


def write(name, take):
    a = load(name, take)
    if name in SOFTEN:
        a = soften(a)
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"{name}.ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
                    "-af", level_af(stats(a), target_db(name)), "-ac", "1", "-ar", str(SR), "-c:a", "libvorbis",
                    "-q:a", "5", "-map_metadata", "-1", dst], input=a.astype("<f4").tobytes(), check=True)
    o = stats(decode(dst))
    print(f"{name}: take {take} -> {os.path.relpath(dst, REPO)}  dur {o['dur']:.2f}s  peak {o['peak_db']:.1f} dB  "
          f"rms-peak {o['rms_peak_db']:.1f} dB  centroid {o['centroid']:.0f} Hz")
    bad = check(name, o)
    if bad:
        sys.exit(f"{name}: 輸出不合格：{'；'.join(bad)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--pick", nargs="*", default=[], help="name=take 或 name=v<N>:<ID>，覆寫 SPEC 的選定候選")
    ap.add_argument("names", nargs="*", help="--write 只寫這幾條（預設 SPEC 全部）")
    a = ap.parse_args()
    picks = {n: t for n, (_, t) in SPEC.items()}
    picks.update(dict(p.split("=", 1) for p in a.pick))
    unknown = [n for n in a.names if n not in picks]
    if unknown:
        sys.exit(f"SPEC 沒有：{', '.join(unknown)}")
    if not a.write:
        vers = sorted((d[4:] for d in os.listdir(REVIEW) if d.startswith("sfx-v")), key=lambda v: int(v[1:]))
        for name in SPEC:
            vtakes = [f"{v}:{f[len(name) + 1:-4]}" for v in vers for f in sorted(os.listdir(os.path.join(REVIEW, f"sfx-{v}")))
                      if f.startswith(name + "_") and f.endswith(".wav")]
            for take in [*range(1, 17), *vtakes]:
                path = src_path(name, take)
                if not os.path.exists(path):
                    continue
                a_ = decode(path)
                if a_.size < SR // 100:
                    print(f"{name}_{take}: NG: 空檔（--trim 把整條當成靜音剪掉）")
                    continue
                s = stats(a_)
                bad = check(name, s)
                print(f"{name}_{take}: dur {s['dur']:.2f}s active {s['active']:.2f}s onset {s['onset']:.3f}s hits {s['hits']} "
                      f"peak {s['peak_db']:.1f} dB rms-peak {s['rms_peak_db']:.1f} dB loudest@{s['loudest']:.2f}s "
                      f"centroid {s['centroid']:.0f} Hz  {'OK' if not bad else 'NG: ' + '；'.join(bad)}\n    env dB {s['env']}")
        return
    for name, take in picks.items():
        if a.names and name not in a.names:
            continue
        if take is None:
            print(f"{name}: 還沒選候選，略過（SPEC 或 --pick）")
            continue
        write(name, take)


if __name__ == "__main__":
    main()
