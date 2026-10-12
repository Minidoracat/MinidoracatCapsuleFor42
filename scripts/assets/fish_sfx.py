# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""第 8 版候選：Fish Audio 的音效生成器（只有網頁版、沒有公開 API；這裡送的是網頁按「生成」時的同一個請求
POST https://api.fish.audio/task，type sound-effect-generation）。網頁標價每次固定 5,000 點，和時長（1–60 s）、steps
（25 草稿／50 高品質）都無關（2026-10-12 實測）；Plus 方案每月 250,000 點、每月重置。所以每次生成要 4 個分開的 take、
中間留 1 秒靜音，再依靜音切開：一次 5,000 點拿 3–4 條候選。提示詞沿用 ElevenLabs 那一條（scripts/assets/sfx_v8.json，
id 相同），切出的檔給 build_sfx／pick_sfx 當 `v8:<ID>_<n>` 讀（temp/assets-review/sfx-v8/raw/）。

    uv run scripts/assets/fish_sfx.py gen [ID ...]     # 送出生成，原檔存 temp/assets-review/sfx-v8/fish/<ID>.wav（已有的略過）
    uv run scripts/assets/fish_sfx.py split [ID ...]   # 原檔 → raw/<ID>_<n>.wav，每條從起音截到該段長度上限

授權：~/.fish-audio/credentials.json（skill fish-audio-tts 的 `auth --from-curl`：網頁登入的 Bearer 加 x-team-id、
x-workspace-id）。
"""
import json
import os
import sys
import time
import urllib.request
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_sfx as bs  # noqa: E402

API = "https://api.fish.audio"
DIR = os.path.join(bs.REVIEW, "sfx-v8")
TAKES, GAP = 4, 1.0  # takes asked for per generation, seconds of silence asked between them
WRAP = ("Four separate takes of the same sound effect, one after another, each isolated by one second of complete "
        "silence: {}")
CAP = {"Throw": bs.THROW[1], "Pop": bs.POP[1], "Pack": bs.PACK[1], "Button": bs.BUTTON[1]}  # longest a take may run
LO = {"Throw": bs.THROW[0], "Pop": bs.POP[0], "Pack": bs.PACK[0], "Button": bs.BUTTON[0]}  # shorter = a fragment
# The model often leaves low noise instead of true silence between takes: -35 dB re the file peak splits those
# (in the 24 files -45 dB found 50 takes, -35 dB 58; -30 dB cut single sounds at their dips).
SILENT_DB, MIN_GAP, FADE = -35.0, 0.25, 0.12


def manifest(ids):
    rows = json.load(open(os.path.join(HERE, "sfx_v8.json"), encoding="utf-8"))
    unknown = set(ids) - {r["id"] for r in rows}
    if unknown:
        sys.exit(f"sfx_v8.json has no {sorted(unknown)}")
    return [r for r in rows if not ids or r["id"] in ids]


def call(method, path, payload=None):
    creds = json.load(open(os.path.join(os.path.expanduser("~"), ".fish-audio", "credentials.json"), encoding="utf-8"))
    h = {"authorization": "Bearer " + creds["token"], "content-type": "application/json", "origin": "https://fish.audio",
         "x-team-id": creds["team_id"], "x-workspace-id": creds.get("workspace_id", creds["team_id"])}
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    with urllib.request.urlopen(urllib.request.Request(API + path, data=data, headers=h, method=method), timeout=60) as r:
        return json.loads(r.read())


def download(url, dst):
    req = urllib.request.Request(url, headers={"user-agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as resp, open(dst, "wb") as f:
        f.write(resp.read())


def originals(sid):
    """The downloaded generations of one manifest line: fish/<ID>.wav, fish/<ID>-2.wav, ..."""
    d = os.path.join(DIR, "fish")
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f == f"{sid}.wav" or f.startswith(f"{sid}-"))


def gen(rows):
    """Each line: download every finished generation of the same prompt already in the account's history (paid
    for, never pay twice), else submit one new generation and wait for it."""
    os.makedirs(os.path.join(DIR, "fish"), exist_ok=True)
    done = {}
    for it in call("GET", "/tools/sound-effects/generate/history/v2?page_size=100").get("items", []):
        if it.get("state") == "finished" and it.get("file_url"):
            done.setdefault(it["prompt"], []).append(it["file_url"])
    for r in rows:
        urls = done.get(WRAP.format(r["text"]), [])
        if not urls and not originals(r["id"]):
            task = call("POST", "/task", {"type": "sound-effect-generation", "prompt": WRAP.format(r["text"]),
                                          "duration": int(min(60, round(TAKES * (r["take"] + GAP)))),  # whole seconds
                                          "steps": 50, "guidance": 5})
            t0 = time.time()
            while task.get("state") not in ("finished", "failed") and time.time() - t0 < 300:
                time.sleep(3)
                task = call("GET", f"/task/{task['_id']}")
            if task.get("state") != "finished" or not task.get("result"):
                print(f"{r['id']}: {task.get('state')} {task.get('generate_error') or (task.get('metadata') or {}).get('error')}")
                continue
            print(f"{r['id']}: new task {task['_id']} credits {task.get('credit_count')} {time.time() - t0:.0f}s")
            urls = [task["result"]]
        for k, url in enumerate(urls, 1):
            dst = os.path.join(DIR, "fish", f"{r['id']}.wav" if k == 1 else f"{r['id']}-{k}.wav")
            if not os.path.exists(dst):
                download(url, dst)
        print(f"{r['id']}: {len(originals(r['id']))} generation(s) on disk")


def segments(a, lo):
    """Runs louder than SILENT_DB (re the file peak, 20 ms RMS) split by at least MIN_GAP of quiet, lo s or longer."""
    w = int(0.02 * bs.SR)
    env = np.sqrt(np.convolve(a * a, np.ones(w) / w, mode="same"))
    loud = 20 * np.log10(env / (env.max() + 1e-12) + 1e-12) > SILENT_DB
    edges = np.flatnonzero(np.diff(np.concatenate([[0], loud.astype(np.int8), [0]])))
    merged = []
    for s, e in zip(edges[::2], edges[1::2]):  # rises and falls alternate: [start, end) of each loud run
        if merged and (s - merged[-1][1]) < MIN_GAP * bs.SR:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    return [(s, e) for s, e in merged if e - s >= lo * bs.SR]


def write_wav(path, a):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(bs.SR)
        f.writeframes((np.clip(a, -1, 1) * 32767).astype("<i2").tobytes())


def split(rows):
    os.makedirs(os.path.join(DIR, "raw"), exist_ok=True)
    for r in rows:
        files = originals(r["id"]) if os.path.isdir(os.path.join(DIR, "fish")) else []
        if not files:
            print(f"{r['id']}: nothing in {os.path.relpath(os.path.join(DIR, 'fish'), bs.REPO)}")
            continue
        for f in os.listdir(os.path.join(DIR, "raw")):
            if f.startswith(r["id"] + "_"):
                os.remove(os.path.join(DIR, "raw", f))
        cap, lo = (next(v for k, v in m.items() if r["id"].startswith(k)) for m in (CAP, LO))
        lens, n = [], 0
        for src in files:
            a = bs.decode(src)
            for s, e in segments(a, lo)[:TAKES]:
                x = a[s:e]
                onset = max(0, int(np.argmax(np.abs(x) > 0.1 * np.abs(x).max())) - int(0.005 * bs.SR))
                x = x[onset:onset + int(cap * bs.SR)].copy()
                if onset + int(cap * bs.SR) < e - s:  # cut short: fade the end instead of a click
                    k = min(len(x), int(FADE * bs.SR))
                    x[-k:] *= np.linspace(1, 0, k)
                n += 1
                write_wav(os.path.join(DIR, "raw", f"{r['id']}_{n}.wav"), x)
                lens.append(f"{len(x) / bs.SR:.2f}")
        print(f"{r['id']}: {len(lens)} takes from {len(files)} file(s)  {' '.join(lens)} s")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("gen", "split"):
        sys.exit(__doc__)
    rows = manifest(sys.argv[2:])
    gen(rows) if sys.argv[1] == "gen" else split(rows)


if __name__ == "__main__":
    main()
