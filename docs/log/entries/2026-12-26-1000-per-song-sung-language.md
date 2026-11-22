# [2026-12-26 10:00] Per-song sung language and failed-draft notice

- Scope: round 42, proofreading and recognition UI cleanup (D-062).
  - Project page (desktop, with audio): `ProjectSungLanguageSelector` sets 演唱语言 for one song in `metadata.sungLanguage` (自动判断 removes it). Saved with `updateProjectIfUnchanged`; a conflict asks to choose again; with lyrics a snackbar offers 重新识别. The metadata row 识别语言 became 演唱语言 (`SpokenLanguageResolution.describeProject`), and the document chip shows the language name.
  - `SpokenLanguageSource.project`: `LocalProjectTranscriptionWorkflow` uses the song's language over the settings without probing; `SpokenLanguagePolicy.forProject` / `applyResolution` give the same language to span recognition and independent reruns. The resolution is also written to the draft's `metadata.spokenLanguage`.
  - Recognition settings: 自动判断 plus zh/en/ja/ko/fr/de/es/ru (`SpokenLanguagePolicy.selectableLanguages`); a saved value is normalised so the dropdown always has it. Qwen3-ASR maps fr/de/es/ru.
  - Lyric editor: `RecognitionReviewSummary` reads the draft's sung language (`sungLanguageLine`) and flags a draft that looks failed (`looksFailed`: at most 3 rows, or a hallucination-prone language nobody chose, before any review). `LyricRecognitionSummaryCard` shows the notice with 回工程页 (through the editor's unsaved-edits guard) and 演唱语言 in the expanded details. The toolbar shows the language name instead of `ZH`.
- Files:
  - New: `lib/features/project/presentation/widgets/project_sung_language_selector.dart`, `test/features/project/presentation/widgets/project_sung_language_selector_test.dart`, `test/features/lyrics/presentation/widgets/lyric_recognition_language_test.dart`.
  - Changed: `lib/features/transcription/domain/models/spoken_language.dart`, `lib/features/transcription/data/services/{local_project_transcription_workflow,project_span_recognition_service,independent_project_rerun_service,qwen3_asr_native_transcription_service}.dart`, `lib/features/transcription/presentation/widgets/transcription_config_dialog.dart`, `lib/features/project/presentation/screens/project_detail_screen.dart`, `lib/features/lyrics/domain/models/recognition_review_summary.dart`, `lib/features/lyrics/presentation/widgets/{lyric_recognition_summary_card,lyric_editor_content,lyric_editor_toolbar}.dart`.
  - Tests: `test/features/transcription/spoken_language/spoken_language_policy_test.dart`, `test/features/transcription/vocal_gap_fill/workflow_vocal_gap_fill_test.dart`, `test/features/transcription/presentation/vocal_gap_fill_setting_test.dart`, `test/features/project/presentation/project_detail_capability_test.dart`, `test/features/lyrics/presentation/widgets/lyric_editor_toolbar_test.dart`.
  - `docs/decisions.md` (D-062), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate.
- Notes:
  - Lyrics must not import transcription, so `RecognitionReviewSummary` keeps its own copy of the hallucination-prone language list and labels; a test keeps the list equal to `SpokenLanguagePolicy.hallucinationProne`.
  - The selector is desktop-only like the rest of recognition (mobile hides recognition options since round 37).
- Commit: `Let each song set its sung language and flag failed drafts`
