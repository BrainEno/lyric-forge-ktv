# [2026-11-21 18:00] Keep unplaced aligner words and check missed repeats

- Scope: Follow-up the user asked for. Outro chants and ad-libs come out shortened, and sometimes too early. Proofreading should point out where "这里可能漏了重复的和声" (a repeated chant may be missing here) (D-025).
  - Root cause found while building the check.
    - The Qwen3 forced aligner returns words it cannot place with zero length, piled on one instant, and stretches the next word over the skipped singing.
    - `_parseTimedToken` dropped every `end <= start` word. That was 12–53 % of the recognised words per song on the D-024 recognitions, most of them in chants.
    - Ridgway (1.7B) lost "Whoa I'm paddling on I'm paddling strong Whoa find the fire find the" and kept a single "fire" spanning 223.4–247.9 s.
  - `lib/features/transcription/domain/models/aligner_word_timing_repair.dart` (new).
    - Clusters of consecutive zero-length words starting within 30 ms, plus the word that ends them, are spread over the cluster's span by letter count.
    - If the span is longer than 1.2 s per word, the cluster goes at the end of the span.
    - If the span is shorter than 80 ms per word, it is extended towards the next word, by at most 350 ms per word.
    - If there is no room, the words keep zero length.
  - `qwen3_asr_native_transcription_service.dart`: word-level tokens may be zero-length and are repaired before grouping, both top-level `timestamps.items` and nested segment `words`. Segment-level rows still need a length.
  - `lyric_missed_repeat_detector.dart` (new). It reports three things:
    - **crowded words**: 5 or more starting within 30 ms. The fix clears the row's word timing, selected by default.
    - **stretched words**: 6 s or more, inside the row's span.
      - First word: the word and the row start are trimmed to 0.8 s before the word's end, selected by default.
      - Last word: the word and the row end are trimmed to 0.8 s after the word's start. Not selected by default, because it may be a held note.
      - Middle word: listen only.
    - **gap after a chant**: at least 8 s without lyrics after a chant row, in the last 40 % of the song or before the same chant resumes.
      - A chant row is mostly vocables, a phrase repeated back to back in the row, or a short line that occurs 3 or more times (only near the end).
      - The fix inserts up to 8 copies at the row's own spacing, with fresh ids and unscored confidence. Row-indexed review metadata is remapped. Not selected by default.
  - `lyric_missed_repeat_dialog.dart` (new):
    - Per-finding checkbox and −/+ for the copy count (changing the count ticks the finding).
    - Row audition, plus audition of the gap, stretched span or crowded span through `previewProofreadTimedLine`.
    - One undoable edit.
  - Wiring:
    - `LyricBatchTextTool.missedRepeatCheck` and `LyricProofreadAction.missedRepeatCheck`.
    - Toolbar and content menus.
    - The coordinator passes the audio duration and a span preview.
    - Draft health `missedRepeatSpots` and the summary-card hint "可能漏唱的和声 N 处".
- Experiment: the twelve raw recognitions from the D-024 runs (six CC-licensed JamendoLyrics songs × 0.6B/1.7B) were re-parsed offline with a Python port of the old and new parsing.

  | model | song | WER old parser | WER new parser |
  |---|---|---|---|
  | 0.6B | Avercage | 0.87 | 0.73 |
  | 0.6B | Kinematic | 0.48 | 0.23 |
  | 0.6B | Ridgway | 0.46 | 0.35 |
  | 0.6B | Songwriterz | 0.55 | 0.54 |
  | 0.6B | The madpix project | 0.33 | 0.25 |
  | 0.6B | The Rinn | 0.68 | 0.52 |
  | 1.7B | Avercage | 0.81 | 0.64 |
  | 1.7B | Kinematic | 0.48 | 0.22 |
  | 1.7B | Ridgway | 0.47 | 0.33 |
  | 1.7B | Songwriterz | 0.49 | 0.43 |
  | 1.7B | The madpix project | 0.36 | 0.19 |
  | 1.7B | The Rinn | 0.68 | 0.50 |

  - Mean: 0.6B 0.562 → 0.437; 1.7B 0.548 → 0.383. The D-024 figures were computed on the raw JSON text and did not include the dropped words.
  - Recovered words per song: for example Avercage 1.7B, 67 → 137 words; Songwriterz 0.6B, 139 → 297.
  - Ridgway 1.7B outro after the change: "Whoa I'm paddling on I'm paddling / strong Whoa find the fire find / the fire Whoa I'm paddling" from 231.1 s (reference 238–255 s), and "Find the fire" ×4.
  - Runs of 3–4 zero-length words at one instant occur 5–17 times per song, so the crowded threshold is 5. Stretched words in the raw data ran 6.6–25.6 s; most are an intro swallowed by the first word (12–25 s early).
- Files:
  - New: `aligner_word_timing_repair.dart`, `lyric_missed_repeat_detector.dart`, `lyric_missed_repeat_dialog.dart`.
  - Changed: `qwen3_asr_native_transcription_service.dart`, `lyric_draft_health_service.dart`, `lyric_batch_text_edit.dart`, `lyric_batch_text_tools_coordinator.dart`, `lyric_proofread_menu_button.dart`, `lyric_editor_toolbar.dart`, `lyric_editor_content.dart`, `lyric_recognition_summary_card.dart`.
  - Tests:
    - New: `aligner_word_timing_repair_test.dart`, `lyric_missed_repeat_detector_test.dart`, `lyric_missed_repeat_dialog_test.dart`.
    - Changed: two zero-length cases in `qwen_runtime_service_lifecycle_test.dart`, and a `transcribeResult` knob in `fake_qwen_runtime.dart`.
  - Docs: `decisions.md` (D-025), `high_quality_asr.md`, handoff.
- Validation: the sandbox has no Dart/Flutter toolchain. A temporary branch workflow ran `dart format`, `flutter analyze`, the targeted tests, the full suite and the work-log tool on GitHub Actions, and was deleted before the PR update.
- Notes:
  - Where the skipped singing sits inside a stretched span is still a guess, so the recovered words' timing is an estimate.
  - Existing drafts need re-recognition to get the dropped words back.
  - The thresholds (5 words, 6 s, 8 s, 40 %) are empirical, from six English songs.
- Commit: `Keep unplaced aligner words; missed-repeat check`
