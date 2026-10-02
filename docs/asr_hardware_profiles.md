# ASR Hardware Profiles

LyricForge keeps project data portable and resolves model/runtime choices per
machine immediately before local transcription.

A project does not need to know whether it is opened on an RTX workstation or
an Intel iMac. It stores transcription results and quality metadata; the local
machine profile resolves the actual backend.

## Automatic profile selection

The current automatic resolver supports the two high-end machines used during
development.

### Windows RTX 5080

Detection:

- Windows
- NVIDIA GPU detected through `nvidia-smi`
- GPU name contains `RTX 5080`

Resolved profile:

```text
RTX 5080 Highest Quality

Primary:
  Qwen3-ASR 1.7B
  CUDA
  BF16

Alignment:
  Qwen3 ForcedAligner 0.6B

Second opinion:
  Whisper large-v3
  full-song pass
```

This remains the quality-first path for the 16 GB RTX 5080 system.

### Intel Mac

Detection:

- macOS
- `uname -m` reports `x86_64` / `amd64`

The GPU model does not determine profile eligibility. This is intentional:
current Qwen native acceleration paths used by LyricForge are not based on an
AMD CUDA backend, so the Radeon GPU is informative rather than the primary
runtime selector.

Resolved profile:

```text
Intel Mac High Quality

Primary:
  Whisper large-v3
  whisper.cpp
  x86 CPU

Second opinion:
  Qwen3-ASR 0.6B
  CPU / f32

Second-opinion alignment:
  Qwen3 ForcedAligner 0.6B
```

For the 2020 27-inch iMac development machine the expected hardware is:

- 10-core Intel Core i9 3.6 GHz
- 40 GB DDR4
- AMD Radeon Pro 5700 XT 16 GB
- macOS x86_64

The 40 GB system memory makes the 0.6B Qwen + aligner path practical without
making the heavier 1.7B CPU path the default.

## Why the engine order changes

On the RTX 5080 system, Qwen3-ASR 1.7B has a fast CUDA path, so it remains the
primary transcript and Qwen ForcedAligner is the timing authority.

On Intel macOS, the same Qwen path falls back to CPU. Whisper.cpp is therefore
used as the primary full-song recognizer and Qwen3-ASR 0.6B becomes an
independent second opinion.

The comparison layer is engine-agnostic:

- match lines by timestamp overlap;
- compare normalized Unicode text;
- identify low-confidence / repeated / timing-abnormal output;
- only auto-replace when the alternate result is materially stronger;
- otherwise surface the alternative in the lyric editor.

For the Intel Mac profile, automatic Qwen text replacement preserves the
Whisper primary line timing. Qwen ForcedAligner timestamps are still used when
matching and evaluating the second-opinion candidate.

## Local settings vs project metadata

Machine-local settings include:

- executable paths
- model paths / model IDs
- hardware profile preference
- Qwen device and dtype
- FFmpeg location
- Whisper runtime/model

Project metadata records only portable facts such as:

- resolved profile name
- primary model family
- fallback model family
- language
- generated timestamps/results

Absolute runtime/model paths are not persisted into project metadata.

## Manual override

The settings UI offers:

- Automatic
- RTX 5080 Highest Quality
- Intel Mac High Quality
- Custom

Automatic is recommended for the two current development machines.

Custom preserves the exact manually entered engine order/device/model settings
and bypasses automatic model selection.

## Hardware detection

### Windows

LyricForge uses:

```text
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits
```

### macOS

LyricForge uses:

```text
uname -m
sysctl -n machdep.cpu.brand_string
sysctl -n hw.memsize
system_profiler -json SPDisplaysDataType
```

Hardware detection is best-effort. Failure to read optional GPU metadata does
not prevent the Intel Mac profile from resolving because x86_64 macOS is the
decisive signal for that profile.

## Future profiles

The architecture is intended to add, without changing project workflow:

- Apple Silicon / Metal
- general NVIDIA >= 12 GB
- lower-memory Windows PCs
- CPU-only low-resource mode
- packaged sherpa-onnx / Qwen 0.6B INT8 mode
