#!/usr/bin/env python3
"""Checks what lyricforge-separator wrote for a smoke-test song.

  check_stems.py <input.wav> <stem dir> <separator stdout log>

Verifies the stdout protocol (provider, monotonic progress ending at 1, stats,
done marker), that vocals.wav and accompaniment.wav are 44.1 kHz stereo
16-bit with exactly the input length, that the vocal stem is neither silent
nor a copy of the mix, and that vocals + accompaniment reconstruct the mix.
"""

import math
import struct
import sys
import wave
from pathlib import Path


def read(path: Path):
    with wave.open(str(path), "rb") as handle:
        if handle.getframerate() != 44100:
            raise SystemExit(f"{path}: rate {handle.getframerate()} != 44100")
        if handle.getnchannels() != 2 or handle.getsampwidth() != 2:
            raise SystemExit(f"{path}: expected 16-bit stereo")
        raw = handle.readframes(handle.getnframes())
    return struct.unpack(f"<{len(raw) // 2}h", raw)


def rms(samples) -> float:
    return math.sqrt(sum(s * s for s in samples) / max(len(samples), 1)) / 32768


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    mix_path, stem_dir, log_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])

    log = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    providers = [line.split()[1] for line in log if line.startswith("LF_PROVIDER ")]
    progress = [float(line.split()[1]) for line in log if line.startswith("LF_PROGRESS ")]
    stats = [line for line in log if line.startswith("LF_STATS ")]
    if not providers:
        raise SystemExit("no LF_PROVIDER line")
    if not progress or progress[-1] != 1.0:
        raise SystemExit(f"progress did not reach 1.0: {progress[-3:]}")
    if any(b < a for a, b in zip(progress, progress[1:])):
        raise SystemExit("progress went backwards")
    if len(stats) != 1 or not log[-1].startswith("LF_DONE vocals="):
        raise SystemExit("missing LF_STATS or final LF_DONE line")
    if any(line.startswith("LF_ERROR") for line in log):
        raise SystemExit("separator reported an error")

    mix = read(mix_path)
    vocals = read(stem_dir / "vocals.wav")
    accompaniment = read(stem_dir / "accompaniment.wav")
    if not len(mix) == len(vocals) == len(accompaniment):
        raise SystemExit(
            f"length mismatch: mix {len(mix)}, vocals {len(vocals)}, "
            f"accompaniment {len(accompaniment)}"
        )

    mix_rms, vocal_rms, acc_rms = rms(mix), rms(vocals), rms(accompaniment)
    worst = max(abs(m - (v + a)) for m, v, a in zip(mix, vocals, accompaniment))
    print(f"provider={providers[-1]} mix_rms={mix_rms:.4f} vocals_rms={vocal_rms:.4f} "
          f"accompaniment_rms={acc_rms:.4f} reconstruction_error={worst} LSB")
    print(stats[0])
    if vocal_rms < 1e-4:
        raise SystemExit("vocal stem is silent")
    if abs(vocal_rms - mix_rms) < 1e-4 and acc_rms < 1e-4:
        raise SystemExit("vocal stem is a copy of the mix")
    # Two independent 16-bit roundings, plus clamping on rare peaks.
    if worst > 4:
        raise SystemExit(f"vocals + accompaniment differ from the mix by {worst} LSB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
