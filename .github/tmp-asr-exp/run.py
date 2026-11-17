"""Temporary experiment: run qwen3-asr-rs the way LyricForge does on real songs.

Not part of the product. Deleted before the PR.
"""
import argparse, csv, json, os, subprocess, sys, time, wave

SONGS = [
    # (file stem, artist, title)
    ("Ridgway_-_Fire_Inside", "Ridgway", "Fire Inside"),
    ("Avercage_-_Embers", "Avercage", "Embers"),
    ("The_Rinn_-_Voices__2017_Version_", "The Rinn", "Voices"),
    ("The.madpix.project_-_One_Way_Street", "The.Madpix.Project", "One Way Street"),
    ("Songwriterz_-_Back_In_Time", "Songwriterz", "Back In Time"),
    ("Kinematic_-_Peyote", "Kinematic", "Peyote"),
]
GATED = {"Ridgway_-_Fire_Inside", "Kinematic_-_Peyote", "Avercage_-_Embers"}


def wav_seconds(path):
    with wave.open(path) as w:
        return w.getnframes() / w.getframerate()


def reference(stem, songs):
    rows = list(csv.DictReader(open(os.path.join(songs, stem + ".csv"))))
    return [(float(r["start_time"]), float(r["end_time"]), r["lyrics_line"]) for r in rows]


def prepare(stem, songs, gated):
    src = os.path.join(songs, stem + ".mp3")
    out = os.path.join(songs, stem + (".gated" if gated else "") + ".wav")
    if os.path.exists(out):
        return out
    cmd = ["ffmpeg", "-nostdin", "-y", "-loglevel", "error", "-i", src]
    if gated:
        # Simulate a separated vocal stem: everything outside the sung lines
        # (plus 0.7 s) drops to -34 dB, like accompaniment leaking through.
        spans = [(max(0, s - 0.7), e + 0.7) for s, e, _ in reference(stem, songs)]
        inside = "+".join(f"between(t,{s:.2f},{e:.2f})" for s, e in spans)
        cmd += ["-af", f"volume=0.02:enable='eq({inside},0)'"]
    cmd += ["-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", out]
    subprocess.run(cmd, check=True)
    return out


def budget(config, seconds):
    if config["chunk"] is None:
        return max(1024, 256 + int(min(seconds, 1200)) * 8)
    return config["base"] + int(config["chunk"]) * 8


CONFIGS = {
    # What the app sends today.
    "current": {"chunk": None, "context": True},
    "current_noctx": {"chunk": None, "context": False},
    # Same 180 s chunks, budget sized for one chunk.
    "chunk180": {"chunk": 180, "context": True, "base": 256},
    "chunk60": {"chunk": 60, "context": True, "base": 128},
    "chunk30": {"chunk": 30, "context": True, "base": 128},
    "chunk30_noctx": {"chunk": 30, "context": False, "base": 128},
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bin", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--aligner", required=True)
    p.add_argument("--songs", required=True)
    p.add_argument("--config", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--only", default="")
    a = p.parse_args()
    config = CONFIGS[a.config]
    os.makedirs(a.out, exist_ok=True)
    inputs = []
    for stem, artist, title in SONGS:
        if a.only and stem not in a.only.split(","):
            continue
        inputs.append((stem, artist, title, False))
        if stem in GATED:
            inputs.append((stem, artist, title, True))
    for stem, artist, title, gated in inputs:
        name = stem + (".gated" if gated else "")
        wav = prepare(stem, a.songs, gated)
        seconds = wav_seconds(wav)
        mnt = budget(config, seconds)
        context = f"Song title: {title}. Artist: {artist}" if config["context"] else ""
        cmd = [a.bin, "transcribe", "--model", a.model, "--audio", wav,
               "--context", context, "--language", "English",
               "--max-new-tokens", str(mnt), "--max-batch-size", "4",
               "--bucket-by-length", "--return-timestamps",
               "--forced-aligner", a.aligner]
        if config["chunk"] is not None:
            cmd += ["--chunk-max-sec", str(config["chunk"])]
        started = time.time()
        proc = subprocess.run(cmd, capture_output=True, text=True)
        elapsed = time.time() - started
        chunks = [line.split("\t", 4) for line in proc.stderr.splitlines() if line.startswith("LF_CHUNK\t")]
        record = {
            "song": name, "config": a.config, "model": a.model, "seconds": seconds,
            "maxNewTokens": mnt, "elapsed": elapsed, "exit": proc.returncode,
            "chunks": [{"index": int(c[1]), "offset": float(c[2]), "length": float(c[3]), "raw": c[4]} for c in chunks],
        }
        if proc.returncode == 0:
            out = json.loads(proc.stdout)
            record["result"] = out[0] if isinstance(out, list) else out
        else:
            record["stderr"] = proc.stderr[-4000:]
        with open(os.path.join(a.out, f"{name}.{a.config}.json"), "w") as f:
            json.dump(record, f, ensure_ascii=False)
        print(f"{name} {a.config} exit={proc.returncode} {elapsed:.0f}s mnt={mnt} chunks={len(chunks)}", flush=True)


if __name__ == "__main__":
    main()
