#!/usr/bin/env python3
"""Writes a synthetic 44.1 kHz stereo "song" for the separator smoke tests.

A centred, vibrato-modulated harmonic "voice" with syllable-like gaps sits
over a panned bass line, sustained chords and noise-burst drums. It is not a
quality benchmark - only real recordings are - but it exercises every code
path with realistic levels, lengths and stereo content.
"""

import argparse
import math
import random
import struct
import wave

RATE = 44100


def song(seconds: float, seed: int):
    rng = random.Random(seed)
    frames = int(seconds * RATE)
    chord_roots = [220.0, 174.61, 196.0, 164.81]
    left = [0.0] * frames
    right = [0.0] * frames
    voice_phase = 0.0
    for i in range(frames):
        t = i / RATE
        bar = int(t / 2.0) % len(chord_roots)
        root = chord_roots[bar]

        # Accompaniment: bass, a triad pad and drums.
        bass = 0.18 * math.sin(2 * math.pi * root / 2 * t)
        pad = 0.05 * sum(
            math.sin(2 * math.pi * root * ratio * t) for ratio in (1.0, 1.26, 1.5)
        )
        beat = t % 0.5
        kick = 0.35 * math.exp(-beat * 30) * math.sin(2 * math.pi * 60 * beat)
        snare = 0.0
        if (t % 1.0) >= 0.5 and beat < 0.08:
            snare = 0.12 * math.exp(-beat * 40) * (rng.random() * 2 - 1)

        # Voice: on for 0.35 s of every 0.5 s, gliding over the chord.
        syllable = (t % 0.5) < 0.35
        envelope = math.sin(math.pi * min((t % 0.5) / 0.35, 1.0)) if syllable else 0.0
        pitch = root * 2 * (1 + 0.012 * math.sin(2 * math.pi * 5.5 * t))
        voice_phase += 2 * math.pi * pitch / RATE
        voice = 0.0
        for harmonic, gain in ((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.2), (5, 0.12)):
            voice += gain * math.sin(harmonic * voice_phase)
        voice *= 0.12 * envelope

        left[i] = voice + 0.8 * bass + 0.6 * pad + kick + snare
        right[i] = voice + 0.5 * bass + 0.9 * pad + kick + 0.7 * snare
    return left, right


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("output")
    parser.add_argument("--seconds", type=float, default=15.0)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    left, right = song(args.seconds, args.seed)
    peak = max(max(abs(v) for v in left), max(abs(v) for v in right))
    scale = 0.89 / peak if peak > 0.89 else 1.0
    data = bytearray()
    for l_value, r_value in zip(left, right):
        data += struct.pack(
            "<hh",
            int(round(l_value * scale * 32767)),
            int(round(r_value * scale * 32767)),
        )
    with wave.open(args.output, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(bytes(data))
    print(f"wrote {args.output}: {args.seconds} s, {len(left)} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
