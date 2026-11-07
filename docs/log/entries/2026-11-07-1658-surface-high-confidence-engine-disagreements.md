# [2026-11-07 16:58] Surface unreviewed high-confidence engine disagreements

- Scope: Fix issue #332 so an unreviewed dual-engine disagreement is not hidden merely because the model confidence is 100; explicit review decisions control the queue and candidate visibility.
- Files: `lyric_review_priority_service.dart`, `lyric_list_pane.dart`, `lyric_inspector_pane.dart`, their focused tests, `docs/handoff.md`, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs are unavailable. Focused tests, full quality gate, formatter and work-log new/write/check passed on preliminary GitHub Actions run 42357701799 using the pinned SDK; consult the PR for final-head results. `git diff --check` was run locally.
- Notes: The existing confidence-based repetition heuristic is a separate false-positive control, not a review decision. Real-device responsive editor behavior remains unverified.
- Commit: `fix: surface unreviewed engine disagreements`
