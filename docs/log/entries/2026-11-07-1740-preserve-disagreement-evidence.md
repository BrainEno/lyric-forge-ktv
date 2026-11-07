# [2026-11-07 17:40] Preserve disagreement evidence beyond highlight limit

- Scope: Keep all dual-engine candidates and apply replacements independently of the editor highlight limit (#333).
- Files: High-quality and resumable transcription services, transcription configuration dialog, lyric list pane, their tests, work-log documents, and handoff.
- Validation:
  - dart format changed Dart files after dependency resolution => passed in temporary GitHub Actions validation.
  - bash scripts/quality_gate.sh --skip-pub-get => passed in temporary GitHub Actions validation, including analyzer and full suite.
  - flutter test --no-pub --reporter expanded for both transcription services and lyric list => passed in temporary GitHub Actions validation.
- Notes: Older projects cannot recover previously truncated candidates without re-recognition; old dual-engine chunk checkpoints are invalidated. Candidate evidence still uses row indices and structural editing clears it. Real-device responsive checks were not performed.
- Commit: `Preserve all engine disagreement candidates`
