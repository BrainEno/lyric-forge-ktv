# [2026-10-25 01:08] Fix Qwen audio attention matmul tensor layouts

- Scope: Fix the pinned Candle/Qwen3-ASR eager audio attention path that passed non-contiguous tensors into matmul, causing the real-audio self-check failure. Patch the pinned upstream source identically for Windows CUDA and Intel Mac, stamp and enforce the patched runtime version, and update old installed bundles instead of silently retaining them.
- Files: `.github/workflows/build-asr-runtime.yml`, `tool/patches/qwen-audio-attention-contiguous.patch`, `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`, runtime build contract tests, installation troubleshooting docs and work-log navigation.
- Validation: The runtime workflow applies the patch against the pinned upstream revision, runs a dedicated strided-tensor regression under each platform feature set, builds both native runtimes and smoke-checks their executables. Full GPU audio inference still needs manual validation on Windows + RTX 5080 after the updated runtime release is published.
- Notes: The repeated audio file was not the cause. The error reports transposed Q/K tensor views that are not contiguous; this is an inference-kernel layout issue. The runtime updater preserves the existing bundle until the downloaded manifest and executables pass validation.
- Commit: `fix: materialize Qwen attention tensors before matmul`
