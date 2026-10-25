# [2026-10-25 19:48] Add native arbitrary-text forced-alignment endpoint

- Scope: Patch the pinned Rust/Candle Qwen server with an explicit `POST /v1/align` endpoint that accepts audio, reference text, and language, returns timestamped items, and never substitutes ASR context for forced alignment.
- Files: tool/patches/qwen3-asr-forced-align-http-endpoint.patch, .github/workflows/build-asr-runtime.yml, docs/high_quality_asr.md, docs/high_quality_asr_windows_setup.md, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added native mock-server integration coverage for missing audio/text/language and endpoint discovery; macOS Intel native workflow runs this test. Native patch application/build and Flutter/work-log checks remain pending remote CI; this environment has no local Rust/Dart/Flutter toolchain.
- Notes: The patch targets pinned qwen3-asr-rs revision `7984967e8701cc90bb17d06453901036e36ca578`. Existing runtime bundles must be rebuilt; this does not claim real-song alignment quality or production UI wiring.
- Commit: `docs: document native arbitrary-text forced alignment endpoint`
