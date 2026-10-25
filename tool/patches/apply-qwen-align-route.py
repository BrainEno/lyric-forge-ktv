#!/usr/bin/env python3
"""Apply the route-only part of the forced-alignment patch without line offsets."""
from pathlib import Path

source = Path("qwen3_asr_cli/src/cmd_serve.rs")
text = source.read_text(encoding="utf-8")
anchor = '        .route("/v1/transcribe", post(transcribe).options(options_ok))'
route = '        .route("/v1/align", post(align).options(options_ok))'

if text.count(anchor) != 1:
    raise SystemExit(
        f"Expected exactly one transcribe route anchor in {source}, found {text.count(anchor)}"
    )
if route in text:
    raise SystemExit(f"{route.strip()} already exists; refusing to apply route twice")

source.write_text(text.replace(anchor, anchor + "\n" + route, 1), encoding="utf-8")
updated = source.read_text(encoding="utf-8")
if updated.count(route) != 1:
    raise SystemExit("Failed to verify exactly one /v1/align route after insertion")
