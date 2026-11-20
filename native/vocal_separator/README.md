# lyricforge-separator

Command-line vocal separator used before lyric recognition (D-043). It runs
the fine-tuned htdemucs vocals model (`htdemucs_ft`, vocals member) exported
to ONNX, through the demucs.onnx inference core in
`third_party/demucs_onnx`, on ONNX Runtime:

- Windows: DirectML (any DirectX 12 GPU, including the RTX 5080 target),
  falling back to the CPU provider when no usable adapter exists;
- other platforms: CPU only (not shipped yet).

```text
lyricforge-separator --model htdemucs_ft_vocals.onnx --input mix.wav \
                     --output-dir stems [--provider auto|dml|cpu]
```

The input must be a 44.1 kHz mono or stereo WAV; the app converts the song
with FFmpeg first. Output is `vocals.wav` and `accompaniment.wav` (mix minus
vocals), 16-bit stereo at 44.1 kHz, written atomically.

Progress and results are printed as `LF_*` lines on stdout (see
`src/report.hpp`); the Dart side parses them in
`lib/features/transcription/data/services/separator_output_parser.dart`.
Exit codes: 0 ok, 2 usage, 3 input, 4 model/provider, 5 output, 6 internal.

## Building

Unit tests (no ONNX Runtime needed; uses a fake engine):

```sh
cmake -S native/vocal_separator -B native-build
cmake --build native-build && ./native-build/lfsep_tests
```

The full tool needs Eigen 3.4 and an ONNX Runtime package:

```sh
cmake -S native/vocal_separator -B sep-build -DLFSEP_BUILD_CLI=ON \
  -DEIGEN_DIR=/usr/include/eigen3 \
  -DORT_INCLUDE_DIR=<ort>/include -DORT_LIBRARY=<ort>/lib/libonnxruntime.so
```

On Windows add `-DLFSEP_WITH_DIRECTML=ON` and use the
`Microsoft.ML.OnnxRuntime.DirectML` NuGet package. The release bundle is
built, smoke-tested and published by
`.github/workflows/build-vocal-separator.yml`; the model is exported there by
`tool/vocal_separator/export_htdemucs_vocals_onnx.py`.
