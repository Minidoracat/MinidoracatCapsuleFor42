# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""車輛膠囊音效：檢查 ElevenLabs 產生的候選檔，挑定的那一條做響度整理後轉成 MOD 用的 .ogg。

步驟（repo 根目錄；生成器見 skill elevenlabs-tts，提示詞在 scripts/assets/sfx.json）：
    python ~/.omp/agent/skills/elevenlabs-tts/scripts/eleven_tts.py sfx --manifest scripts/assets/sfx.json \
        --out-dir temp/assets-review/sfx-takes --format wav --variants 4
    uv run scripts/assets/build_sfx.py              # 只列每條候選的長度、峰值、RMS、起音、尾巴、頻譜重心
    uv run scripts/assets/build_sfx.py --write      # 用 SPEC 選定的候選寫進 MOD 的 media/sound/MinidoracatVehicleCapsule/

第 2 版候選（提示詞 scripts/assets/sfx_v2.json，混音與合成 scripts/assets/design_sfx.py，試聽頁
temp/assets-review/sfx-v2/index.html）用 `v2:<ID>` 指定，例如：
    uv run scripts/assets/build_sfx.py --write --pick VehicleCapsulePop=v2:P3 VehicleCapsuleButton=v2:B4

整理：4 ms 淡入、60 ms 淡出，增益調到 RMS 峰值（50 ms 窗）-18 dBFS，再 alimiter 限在 -1 dBFS；
44.1 kHz 單聲道 Vorbis q5。sound script 在 media/scripts/MinidoracatVehicleCapsule_sounds.txt。
"""
import argparse
import os
import subprocess
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TAKES = os.path.join(REPO, "temp", "assets-review", "sfx-takes")
V2 = os.path.join(REPO, "temp", "assets-review", "sfx-v2")
OUT = os.path.join(REPO, "MOD", "MinidoracatVehicleCapsuleFor42", "Contents", "mods", "MinidoracatVehicleCapsuleFor42",
                   "42", "media", "sound", "MinidoracatVehicleCapsule")
SR = 44100
# 名稱 → (可接受的有聲長度範圍 s, 選定的候選編號)。規格：Pop 0.25–1.6 s（開瓶砰聲較短）、Pack 約 1.0–1.5 s、Button 約 0.3 s。
# 2026-10-10 選定（沒人耳試聽，依波形輪廓挑；用 `uv run scripts/assets/build_sfx.py` 看 env dB）：
#   Pop 12（第 3 輪新提示）：啵 0.2 s → 短暫停頓 → 噗地冒煙升起再淡出，有聲 0.81 s。12 條候選裡
#     「先啵後噗」形狀的只有 2、12 兩條，都短於 1.0 s；長度達標的 1、10 只有一聲啵加衰減，所以下限先放寬到 0.8 s；
#     第 2 版候選加入較短的開瓶砰聲，再放寬到 0.25–1.6 s。
#   Pack 7：持續的吸入咻聲 0.8 s → 停 0.2 s → 啵，有聲 1.07 s，頻譜重心 2.1 kHz（不刺耳）。
#   Button 4：按下「喀」→ 0.2 s 後彈回「嚓」，有聲 0.26 s。
SPEC = {
    "VehicleCapsulePop": ((0.25, 1.6), 12),
    "VehicleCapsulePack": ((1.0, 1.5), 7),
    "VehicleCapsuleButton": ((0.15, 0.5), 4),
}
TARGET_RMS_DB = -18.0


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
    """take：sfx-takes 的編號，或 `v2:<ID>` 指 sfx-v2 的候選。"""
    take = str(take)
    if take.startswith("v2:"):
        return os.path.join(V2, f"{name}_{take[3:]}.wav")
    return os.path.join(TAKES, f"{name}_{take}.wav")


def level_af(s):
    """stats → ffmpeg 濾鏡：剪掉前面的靜音（觸發就出聲）、淡入淡出、增益到 TARGET_RMS_DB、限幅 -1 dBFS。"""
    start = max(0.0, s["onset"] - 0.005)
    end = s["tail"] + 0.06
    return (f"atrim={start:.3f}:{end:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.004,"
            f"afade=t=out:st={end - start - 0.06:.3f}:d=0.06,"
            f"volume={TARGET_RMS_DB - s['rms_peak_db']:.2f}dB,alimiter=limit=0.891:level=0")


def write(name, take):
    src = src_path(name, take)
    af = level_af(stats(decode(src)))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"{name}.ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-af", af, "-ac", "1", "-ar", str(SR),
                    "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", dst], check=True)
    o = stats(decode(dst))
    print(f"{name}: take {take} -> {os.path.relpath(dst, REPO)}  dur {o['dur']:.2f}s  peak {o['peak_db']:.1f} dB  "
          f"rms-peak {o['rms_peak_db']:.1f} dB  centroid {o['centroid']:.0f} Hz")
    bad = check(name, o)
    if bad:
        sys.exit(f"{name}: 輸出不合格：{'；'.join(bad)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--pick", nargs="*", default=[], help="name=take 或 name=v2:<ID>，覆寫 SPEC 的選定候選")
    a = ap.parse_args()
    picks = {n: t for n, (_, t) in SPEC.items()}
    picks.update(dict(p.split("=", 1) for p in a.pick))
    if not a.write:
        for name in SPEC:
            v2 = sorted(f for f in os.listdir(V2) if f.startswith(name + "_") and f.endswith(".wav")) if os.path.isdir(V2) else []
            for take in [*range(1, 17), *(f"v2:{f[len(name) + 1:-4]}" for f in v2)]:
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
        if take is None:
            sys.exit(f"{name}: 還沒選候選（SPEC 或 --pick）")
        write(name, take)


if __name__ == "__main__":
    main()
