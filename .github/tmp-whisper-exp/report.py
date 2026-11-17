"""Temporary experiment report. Deleted before the PR."""
import csv, glob, json, os, re, sys

songs, results, out = sys.argv[1:4]


def norm(text):
    return re.sub(r"[^\w']+", " ", text.lower()).strip()


def words(text):
    return norm(text).split()


def wer(ref, hyp):
    r, h = ref, hyp
    prev = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        cur = [i] + [0] * len(h)
        for j in range(1, len(h) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] != h[j - 1]))
        prev = cur
    return prev[len(h)] / max(1, len(r))


def segments(path):
    data = json.load(open(path, encoding="utf-8", errors="replace"))
    rows = []
    for seg in data.get("transcription", []):
        off = seg.get("offsets", {})
        text = seg.get("text", "").strip()
        if not text:
            continue
        rows.append((off.get("from", 0) / 1000, off.get("to", 0) / 1000, text))
    return rows


def loops(rows):
    """Longest run of consecutive identical rows, and of repeated 2-4 row blocks."""
    keys = [norm(t) for _, _, t in rows]
    best_rows = (1, None)
    run = 1
    for i in range(1, len(keys)):
        run = run + 1 if keys[i] and keys[i] == keys[i - 1] else 1
        if run > best_rows[0]:
            best_rows = (run, rows[i - run + 1][0])
    best_block = (0, None, 0)
    for period in (2, 3, 4):
        for start in range(len(keys)):
            reps = 1
            while start + period * (reps + 1) <= len(keys) and keys[start + period * reps:start + period * (reps + 1)] == keys[start:start + period]:
                reps += 1
            if reps >= 3 and reps * period > best_block[0] * max(1, best_block[2]):
                best_block = (reps, rows[start][0], period)
    return best_rows, best_block


def reference(stem):
    return [(float(r["start_time"]), float(r["end_time"]), r["lyrics_line"]) for r in csv.DictReader(open(os.path.join(songs, stem + ".csv")))]


lines = ["# Whisper large-v3 loop experiment", "", "| song | config | sec | rows | ref rows | WER | WER 2nd half | longest same-row run (at s) | block loop reps x rows (at s) | rows after last ref line + 5 s |", "|---|---|---|---|---|---|---|---|---|---|"]
for path in sorted(glob.glob(os.path.join(results, "*.json"))):
    if path.endswith(".run.json"):
        continue
    name = os.path.basename(path)[:-5]
    stem, config = name.rsplit(".", 1)
    run = json.load(open(os.path.join(results, name + ".run.json")))
    rows = segments(path)
    ref = reference(stem)
    end = ref[-1][1]
    half = (ref[0][0] + end) / 2
    w = wer(words(" ".join(t for *_, t in ref)), words(" ".join(t for *_, t in rows)))
    w2 = wer(words(" ".join(t for s, _, t in ref if s >= half)), words(" ".join(t for s, _, t in rows if s >= half)))
    (rr, rat), (br, bat, bp) = loops(rows)
    tail = sum(1 for s, _, _ in rows if s > end + 5)
    lines.append(f"| {stem} | {config} | {run['seconds']} | {len(rows)} | {len(ref)} | {w:.3f} | {w2:.3f} | {rr} ({rat if rat is None else round(rat)}) | {br}x{bp} ({bat if bat is None else round(bat)}) | {tail} |")
lines.append("")
for path in sorted(glob.glob(os.path.join(results, "*.json"))):
    if path.endswith(".run.json"):
        continue
    name = os.path.basename(path)[:-5]
    lines.append(f"## {name}")
    lines.append("```")
    for s, e, t in segments(path):
        lines.append(f"{s:7.2f} {e:7.2f} {t}")
    lines.append("```")
open(out, "w").write("\n".join(lines) + "\n")
print("\n".join(lines[:30]))
