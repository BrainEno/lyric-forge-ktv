# [2026-12-01 09:30] Drop the version suffix from smart proofreading

- Scope: The last part of audit T-02. The proofreading flow behind the 智能校对 menu item still carried a version suffix in four lib file names, nine test file names and about thirty identifiers, although the menu stopped showing a version long ago (E-02) and no other version exists. Readers looking at `LyricProofreadV2ReviewItem` or `run_proofread_v2_use_case.dart` reasonably went looking for a version one. Following D-035, the suffix is gone: domain types and files drop it (`LyricProofreadReviewItem`, `ProofreadRunOptions`, `RunProofreadUseCase`, `proofread_review_assembler.dart`, `lyric_proofread_dialog.dart` …), and the editor's entry point is named after its menu item, so `proofreadV2` became `smartProofread`, `onProofreadV2` became `onSmartProofread` and `_openProofreadV2` became `_openSmartProofread`. Comments and test titles that said "Proofread V2" now say "smart proofreading". No behaviour or wording changed for the user.
- Files:
  - Renamed (`git mv`): `lib/features/lyrics/domain/proofreading/{proofread_document_composer,proofread_review_assembler,run_proofread_use_case}.dart`, `lib/features/lyrics/presentation/widgets/lyric_proofread_dialog.dart`, and the nine matching tests under `test/features/lyrics/`.
  - Identifier and comment updates across `lib/app/lyric_editor_assembly.dart`, `lib/features/lyrics/` (proposal types, coordinator, editor screen, actions, menu, strings) and `lib/features/transcription/data/services/reference_alignment_audio_guard.dart`, plus the tests that use them.
  - New: `test/architecture/proofread_naming_test.dart` keeps the suffix from coming back and pins the entry point's name to its menu item.
  - `docs/decisions.md` (D-035).
- Validation:
  - Every renamed identifier was checked to be unused before the rename, so nothing collides; the persisted ids that look alike (`'whisper-lyrics-v2'`, the model integrity marker, `flutter-action@v2`) are untouched.
  - Lines that got longer or shorter were rewrapped by hand to match `dart format`; format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - `lyric_editor_orchestration_contract_test.dart` reads the use-case test by path and the screen by method signature; both were updated with the rename.
  - Historic work-log entries and reviews keep the old names: they describe the code as it was.
- Commit: `Drop the version suffix from smart proofreading`
