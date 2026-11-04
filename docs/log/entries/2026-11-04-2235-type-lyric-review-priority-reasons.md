# [2026-11-04 22:35] Type lyric review priority reasons

- Scope: Deliver the first bounded slice of #335 by replacing review-priority UI strings in the lyrics domain with stable reason codes and confidence parameters, then map them to unchanged Chinese labels in presentation.
- Files: `lib/features/lyrics/domain/services/lyric_review_priority_service.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/widgets/lyric_list_pane.dart`, `test/features/lyrics/domain/services/lyric_review_priority_service_test.dart`, `test/features/lyrics/presentation/lyric_review_strings_test.dart`, `test/features/lyrics/presentation/widgets/lyric_editor_toolbar_test.dart`, `test/features/lyrics/presentation/widgets/lyric_list_pane_test.dart`, this entry, generated `docs/work_log.md` and `docs/work_log_archive.md`, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `dart_style` formatter stability => passed for all seven changed Dart files.
  - Static reason-code mapping/test coverage check => passed for all 22 codes; domain priority service contains no Chinese display strings.
  - Pinned Flutter Quality Gate run `41848285307` => passed on code/test head `7e277a7`, including changed-file formatting, analysis, contract and regression tests, and the complete test suite.
  - Local Flutter/Dart analyze and tests => not run because the SDK is unavailable in this workspace. The documentation-only follow-up commit needs its own final-head gate.
- Notes: Scoring, ordering, and existing Chinese wording are unchanged. The Proofread V2 assembler remains a separate follow-up within #335; this slice does not close that issue. PR #342 remains open for review and has not been merged.
- Commit: `docs: record lyric review reason codes`
