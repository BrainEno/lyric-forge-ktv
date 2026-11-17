"""Temporary experiment: run whisper-cli the way LyricForge does. Deleted before the PR."""
import argparse, json, os, subprocess, time

META = {
    "Ridgway_-_Fire_Inside": ("Fire Inside", "Ridgway"),
    "Avercage_-_Embers": ("Embers", "Avercage"),
    "The_Rinn_-_Voices__2017_Version_": ("Voices", "The Rinn"),
    "The.madpix.project_-_One_Way_Street": ("One Way Street", "The.Madpix.Project"),
    "Songwriterz_-_Back_In_Time": ("Back In Time", "Songwriterz"),
    "Kinematic_-_Peyote": ("Peyote", "Kinematic"),
}


def extra(config, song):
    title, artist = META[song]
    if config == "lyrics_v1":
        # WhisperDecodingPolicy with language 'auto': bare names joined by ', '.
        return ["--prompt", f"{title}, {artist}", "--suppress-nst"]
    if config == "standard":
        return []
    if config == "mc0":
        return ["--suppress-nst", "-mc", "0"]
    raise SystemExit(config)


def main():
    p = argparse.ArgumentParser()
    for name in ("bin", "model", "wav", "song", "config", "out"):
        p.add_argument("--" + name, required=True)
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    base = os.path.join(a.out, f"{a.song}.{a.config}")
    cmd = [a.bin, "-m", a.model, "-f", a.wav, "-l", "auto", "-ojf", "-of", base, "-pp", "-t", "4"] + extra(a.config, a.song)
    started = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - started
    open(base + ".log", "w").write(proc.stderr[-20000:])
    json.dump({"cmd": cmd[1:], "exit": proc.returncode, "seconds": round(elapsed, 1)}, open(base + ".run.json", "w"))
    print(a.song, a.config, proc.returncode, round(elapsed, 1))


main()
