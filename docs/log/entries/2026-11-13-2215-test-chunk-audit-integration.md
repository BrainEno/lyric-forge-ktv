# [2026-11-13 22:15] Add chunk audit end-to-end integration tests

- Scope: Add end-to-end integration tests covering chunked dual-engine ASR capture, checkpoint resume, coordinator serialization, repository persistence, audio/revision fail-closed guards, and read-only snapshot dialogs in LyricEditorScreen.
- Files: Chunk workflow integration test, chunk editor review integration test, handoff document, work-log entry and generated navigation docs.
- Validation:
  - dart format --output=none --set-exit-if-changed on changed Dart files => passed.
  - flutter analyze --no-fatal-infos on new integration tests => 0 errors, 0 warnings.
  - flutter test chunk_project_workflow_integration_test.dart and chunk_project_editor_review_integration_test.dart => 41 passed.
  - Focused chunk, verifier, loader, cancellation, snapshot dialog, save-conflict, playback read-failure, and resumable service regression tests => passed.
- Notes: Uses deterministic FFmpeg process stubs and scripted ASR/player doubles rather than real model weights or recordings; real-song ASR accuracy and native accessibility remain unverified and #319 stays open.
- Commit: `Add chunk audit end-to-end integration tests`
