# demucs.onnx inference core

`src/` is the C++ inference core of
[sevagh/demucs.onnx](https://github.com/sevagh/demucs.onnx), revision
`81fa1920bd2b5aa2a39d0f95b35b5e1b8b17a1c0` (MIT, copy in `LICENSE`). It runs
an htdemucs network exported to ONNX with the STFT/iSTFT kept outside the
graph, and does the segment overlap-add that Demucs does in PyTorch.

The ONNX weights are exported in CI from the official `htdemucs_ft` vocals
model by `tool/vocal_separator/export_htdemucs_vocals_onnx.py`, using the
`demucs-for-onnx` package of the same demucs.onnx revision (Demucs is MIT,
Copyright (c) Meta Platforms, Inc. and affiliates).

The command-line program that uses this core lives in
`native/vocal_separator/`; see D-043 in `docs/decisions.md`.

## Changes made for Elysium Player

- `tensor.hpp` no longer includes ONNX Runtime (it only needs Eigen), and the
  ONNX Runtime headers are included by their flat name
  (`<onnxruntime_cxx_api.h>`), which is the layout of the official NuGet and
  release archives.
- The two namespace-scope globals `allocator` and `run_options` became
  `default_allocator()` / `default_run_options()`, created on first use. As
  globals they were constructed during static initialisation in an
  unspecified order relative to the ORT C++ API pointer.
- The random time shift uses a fixed seed, so a song always produces the
  same stem (the cache in the app relies on that).
- Two debug prints per segment were removed; the CLI reports progress on
  stdout in a machine-readable form instead.
- `dsp.hpp` includes `<algorithm>` and `<cmath>` itself (MSVC does not get
  them transitively).

No algorithmic change was made.
