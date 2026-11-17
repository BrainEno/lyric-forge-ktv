"""Summarise the experiment runs into markdown (temporary)."""
import csv, glob, json, os, re, sys
from collections import defaultdict

songs_dir, results_dir, out_path = sys.argv[1:4]


def norm_words(text):
    return re.findall(r"[a-z0-9']+", text.lower().replace("’", "'"))


def reference(stem):
    rows = list(csv.DictReader(open(os.path.join(songs_dir, stem + ".csv"))))
    return [(float(r["start_time"]), float(r["end_time"]), r["lyrics_line"]) for r in rows]


def wer(ref, hyp):
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i] + [0] * len(hyp)
        for j, h in enumerate(hyp, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h))
        prev = cur
    return prev[-1] / max(1, len(ref))


def items(result):
    ts = (result or {}).get("timestamps")
    if isinstance(ts, dict):
        ts = ts.get("items") or ts.get("words") or ts.get("word")
    out = []
    for it in ts or []:
        text = str(it.get("text", "")).strip()
        s = it.get("start_time", it.get("start"))
        e = it.get("end_time", it.get("end"))
        if text and s is not None and e is not None:
            out.append((text, float(s), float(e)))
    return out


def group(tokens):
    # Same rules as Qwen3AsrNativeTranscriptionService._groupTokens.
    lines, buf = [], []
    def flush():
        if buf:
            lines.append((" ".join(t for t, _, _ in buf), buf[0][1], buf[-1][2]))
            buf.clear()
    for tok in tokens:
        if buf:
            prev = buf[-1]
            text = " ".join(t for t, _, _ in buf)
            if (tok[1] - prev[2] >= 0.65 or prev[2] - buf[0][1] >= 7 or len(text) >= 54
                    or re.search(r"[。！？!?；;]$", prev[0])):
                flush()
        buf.append(tok)
    flush()
    return lines


def longest_block_loop(lines):
    keys = [" ".join(norm_words(t)) for t, _, _ in lines]
    best = (1, 1, 0)
    for period in range(1, 5):
        for start in range(len(keys)):
            reps = 1
            while start + (reps + 1) * period <= len(keys) and keys[start + reps * period:start + (reps + 1) * period] == keys[start:start + period]:
                reps += 1
            if reps > best[0] and any(keys[start:start + period]):
                best = (reps, period, start)
    return best


records = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(results_dir, "**", "*.json"), recursive=True))]
rows = []
for r in records:
    stem = r["song"].replace(".gated", "")
    ref = reference(stem)
    ref_words = [w for _, _, l in ref for w in norm_words(l)]
    toks = items(r.get("result"))
    hyp_words = [w for t, _, _ in toks for w in norm_words(t)]
    lines = group(toks)
    outside = sum(1 for t, s, e in toks if not any(a - 1.5 <= (s + e) / 2 <= b + 1.5 for a, b, _ in ref))
    reps, period, start = longest_block_loop(lines)
    loop_at = lines[start][1] if lines else 0
    rows.append({
        "model": "1.7B" if "1.7" in r["model"] else "0.6B", "song": r["song"], "config": r["config"],
        "exit": r["exit"], "elapsed": r["elapsed"], "mnt": r["maxNewTokens"], "chunks": len(r["chunks"]),
        "refLines": len(ref), "lines": len(lines), "words": len(hyp_words), "refWords": len(ref_words),
        "wer": wer(ref_words, hyp_words) if r["exit"] == 0 else None,
        "outside": outside, "loop": f"{reps}x{period}@{loop_at:.0f}s" if reps > 1 else "-",
        "rawMax": max((len(c["raw"]) for c in r["chunks"]), default=0),
    })

cfg_order = ["current", "current_noctx", "chunk180", "chunk60", "chunk30", "chunk30_noctx"]
rows.sort(key=lambda x: (x["model"], x["song"], cfg_order.index(x["config"]) if x["config"] in cfg_order else 99))
md = ["# Qwen3-ASR loop experiment", "",
      "| model | song | config | exit | s | max_new_tokens | chunks | lines (ref) | words (ref) | WER | words outside sung lines | longest block loop | longest chunk raw chars |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
for x in rows:
    w = "-" if x["wer"] is None else f"{x['wer']:.2f}"
    md.append(f"| {x['model']} | {x['song']} | {x['config']} | {x['exit']} | {x['elapsed']:.0f} | {x['mnt']} | {x['chunks']} | {x['lines']} ({x['refLines']}) | {x['words']} ({x['refWords']}) | {w} | {x['outside']} | {x['loop']} | {x['rawMax']} |")

agg = defaultdict(lambda: [0, 0.0, 0, 0, 0])
for x in rows:
    if x["wer"] is None:
        continue
    a = agg[(x["model"], x["config"])]
    a[0] += 1; a[1] += x["wer"]; a[2] += x["outside"]; a[3] += x["lines"]; a[4] += x["refLines"]
md += ["", "## Averages", "", "| model | config | runs | mean WER | words outside sung lines | lines / ref lines |", "|---|---|---|---|---|---|"]
for (m, c), a in sorted(agg.items(), key=lambda kv: (kv[0][0], cfg_order.index(kv[0][1]) if kv[0][1] in cfg_order else 99)):
    md.append(f"| {m} | {c} | {a[0]} | {a[1] / a[0]:.3f} | {a[2]} | {a[3]}/{a[4]} |")

md += ["", "## Raw chunk outputs (first 600 chars)", ""]
for r in records:
    md.append(f"### {r['model'].split('/')[-1]} {r['song']} {r['config']}")
    if r["exit"] != 0:
        md.append("```\n" + r.get("stderr", "")[-1500:] + "\n```")
    for c in sorted(r["chunks"], key=lambda c: c["offset"]):
        md.append(f"- chunk @{c['offset']:.1f}s len {c['length']:.1f}s chars {len(c['raw'])}: `{c['raw'][:600]}`")
    md.append("")
open(out_path, "w").write("\n".join(md) + "\n")
print("\n".join(md[:len(rows) + 30]))
