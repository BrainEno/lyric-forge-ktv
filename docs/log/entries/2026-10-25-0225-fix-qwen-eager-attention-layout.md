# [2026-10-25 02:25] Fix Qwen eager attention matmul layout

- Scope: Fix the native Qwen3-ASR runtime error `matmul is only supported for contiguous tensors` seen on Windows CUDA after model installation. The error strides map directly to Q and transposed K views in the pinned upstream `qwen3_asr/src/model/audio_encoder.rs` eager attention path.
- Change: Add a maintained patch to materialize Q, K-transposed and V attention inputs as contiguous tensors on every backend; apply it after the pinned upstream checkout in both Windows CUDA and Intel macOS runtime builds. Add a Rust regression test for transposed attention views and a LyricForge workflow contract test.
- Validation: GitHub Actions must check patch applicability, run the focused Rust regression on Intel macOS, build/smoke-check both runtime bundles, and run Flutter analysis/tests/work-log lint. This does not replace a real Windows + RTX 5080 audio self-check.
- Root-cause assessment: The error is from tensor strides during Qwen audio-attention matmul, not from reusing an audio file or previous Whisper transcript. Same-input reruns may repeat the same execution path but do not fix the model tensor layout.
- Commit: `fix: make Qwen eager attention matmul inputs contiguous`
