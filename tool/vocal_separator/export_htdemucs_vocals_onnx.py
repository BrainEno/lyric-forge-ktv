#!/usr/bin/env python3
"""Export the fine-tuned htdemucs vocals model to ONNX for lyricforge-separator.

`htdemucs_ft` is a bag of four htdemucs networks, each fine-tuned for one
source; its weight matrix is the identity, so the vocals estimate comes only
from the network whose row selects "vocals". That single network is exported
with the STFT/iSTFT kept outside the graph (the `demucs-for-onnx` variant of
Demucs that ships with sevagh/demucs.onnx), which is what the C++ core in
third_party/demucs_onnx expects.

The exported graph is then run once in ONNX Runtime and compared with
PyTorch on the same random segment; the export fails if they disagree.

Usage (CI, see .github/workflows/build-vocal-separator.yml):

  python export_htdemucs_vocals_onnx.py \
      --demucs-src demucs.onnx/demucs-for-onnx \
      --output out/htdemucs_ft_vocals.onnx

Writes the model and `<output>.json` with its size, SHA-256 and layout.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

MODEL_BAG = "htdemucs_ft"
TARGET_SOURCE = "vocals"
SEGMENT_SAMPLES = 343980  # 7.8 s at 44.1 kHz, the htdemucs training segment
OPSET = 17
# Relative to the largest output magnitude; float32 graph rewrites stay far
# below this, a wrong export (swapped inputs, wrong segment) does not.
MAX_RELATIVE_ERROR = 1e-3


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def pick_source_model(bag, source: str):
    """Returns (index, model) of the bag member that alone produces [source]."""
    sources = list(bag.sources)
    if source not in sources:
        raise SystemExit(f"{MODEL_BAG} has no '{source}' source: {sources}")
    column = sources.index(source)
    weights = [list(map(float, row)) for row in bag.weights]
    owners = [i for i, row in enumerate(weights) if row[column] > 0]
    if len(owners) != 1:
        raise SystemExit(
            f"expected exactly one {MODEL_BAG} member for '{source}', "
            f"weights are {weights}"
        )
    index = owners[0]
    row = weights[index]
    if any(value != 0 for i, value in enumerate(row) if i != column):
        raise SystemExit(f"member {index} is not specific to '{source}': {row}")
    return index, bag.models[index], sources


def stub_diffq() -> None:
    """Lets `demucs.states` import without the `diffq` package.

    `demucs.states` imports diffq at module level, but diffq is only used for
    quantized checkpoints and ships no wheels for current Python versions.
    htdemucs_ft is not quantized; should a quantized state ever be loaded,
    the stub fails loudly instead of producing a wrong model.
    """
    try:
        import diffq  # noqa: F401
        return
    except ImportError:
        pass
    import types

    def unavailable(*_args, **_kwargs):
        raise SystemExit("quantized Demucs checkpoints need the diffq package")

    module = types.ModuleType("diffq")
    module.DiffQuantizer = unavailable
    module.UniformQuantizer = unavailable
    module.restore_quantized_state = unavailable
    sys.modules["diffq"] = module


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--demucs-src", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seed", type=int, default=20261118)
    args = parser.parse_args()

    sys.path.insert(0, str(args.demucs_src.resolve()))
    stub_diffq()
    import numpy as np  # noqa: E402
    import onnx  # noqa: E402
    import onnxruntime as ort  # noqa: E402
    import torch  # noqa: E402
    from torch.nn import functional as F  # noqa: E402
    from demucs.htdemucs import HTDemucs, standalone_magnitude, standalone_spec  # noqa: E402
    from demucs.pretrained import get_model  # noqa: E402

    torch.manual_seed(args.seed)
    bag = get_model(MODEL_BAG)
    index, model, sources = pick_source_model(bag, TARGET_SOURCE)
    if not isinstance(model, HTDemucs):
        raise SystemExit(f"member {index} is {type(model).__name__}, not HTDemucs")
    model.eval()

    training_length = int(model.segment * model.samplerate)
    if training_length != SEGMENT_SAMPLES or model.samplerate != 44100:
        raise SystemExit(
            f"unexpected segment {training_length} at {model.samplerate} Hz; "
            "the C++ core is built for 343980 samples at 44100 Hz"
        )

    waveform = torch.randn(1, 2, SEGMENT_SAMPLES) * 0.1
    waveform = F.pad(waveform, (0, training_length - waveform.shape[-1]))
    spectrum = standalone_magnitude(standalone_spec(waveform))
    inputs = (waveform, spectrum)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with torch.no_grad():
        torch.onnx.export(
            model,
            inputs,
            str(args.output),
            export_params=True,
            opset_version=OPSET,
            do_constant_folding=True,
            input_names=["mix", "spec"],
            output_names=["spec_out", "mix_out"],
        )
        expected = [t.numpy() for t in model(*inputs)]

    graph = onnx.load(str(args.output))
    onnx.checker.check_model(graph)
    meta = graph.metadata_props.add()
    meta.key = "lyricforge.sources"
    meta.value = ",".join(sources)
    meta = graph.metadata_props.add()
    meta.key = "lyricforge.target"
    meta.value = TARGET_SOURCE
    onnx.save(graph, str(args.output))

    session = ort.InferenceSession(
        str(args.output), providers=["CPUExecutionProvider"]
    )
    feeds = {
        session.get_inputs()[0].name: waveform.numpy(),
        session.get_inputs()[1].name: spectrum.numpy(),
    }
    actual = session.run(None, feeds)
    report = []
    for name, want, got in zip(["spec_out", "mix_out"], expected, actual):
        if want.shape != got.shape:
            raise SystemExit(f"{name}: shape {got.shape} != torch {want.shape}")
        scale = float(np.abs(want).max()) or 1.0
        error = float(np.abs(want - got).max()) / scale
        report.append({"output": name, "shape": list(want.shape), "relativeError": error})
        print(f"{name}: shape={want.shape} max relative error={error:.2e}")
        if not error <= MAX_RELATIVE_ERROR:
            raise SystemExit(f"{name}: ONNX Runtime disagrees with PyTorch ({error})")

    vocals_index = sources.index(TARGET_SOURCE)
    sidecar = {
        "schemaVersion": 1,
        "file": args.output.name,
        "bytes": args.output.stat().st_size,
        "sha256": sha256_of(args.output),
        "modelBag": MODEL_BAG,
        "bagMember": index,
        "sources": sources,
        "vocalsIndex": vocals_index,
        "sampleRate": model.samplerate,
        "segmentSamples": SEGMENT_SAMPLES,
        "opset": OPSET,
        "torch": torch.__version__,
        "onnxruntime": ort.__version__,
        "parity": report,
    }
    sidecar_path = args.output.with_name(args.output.name + ".json")
    sidecar_path.write_text(json.dumps(sidecar, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(sidecar, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
