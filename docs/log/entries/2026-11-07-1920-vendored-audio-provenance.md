# [2026-11-07 19:20] Document and test vendored audio backend

- Scope: Record the vendored just_audio_media_kit upstream baseline and local MPV patches, and add continuous unit coverage (#236).
- Files: Vendored backend README, setup helper, adapter and unit tests; Flutter Quality Gate, CI contract test, work-log navigation and handoff.
- Validation:
  - dart format changed Dart files after dependency resolution => passed in temporary GitHub Actions validation.
  - bash scripts/quality_gate.sh --skip-pub-get => passed in temporary GitHub Actions validation, including analyzer and full root test suite.
  - flutter test --no-pub --reporter expanded packages/just_audio_media_kit/test test/ci_workflow_contract_test.dart => passed in temporary GitHub Actions validation.
- Notes: Unit tests inject MPV option writes and do not launch libmpv or verify native playback. Windows/Linux device and unwritable-cache smoke tests remain. The OSC workaround depends on media_kit behavior. Run 42367806986 first failed on an unrelated Media Hub TLS Broken pipe, then passed on rerun.
- Commit: `Document and test vendored audio backend`
