# [2026-12-01 11:00] Group review and playback inputs, close E-06 and S-05

- Scope: Three audit items that were marked partly done. E-04: the lyric editor content still took the review queue and the player as thirteen loose arguments and worked out the visible rows, the valid selection and the playhead row from them. They are now two groups next to the ones in `lyric_editor_actions.dart`: `LyricReviewControls` (queue, priorities, filter, selection, follow-playback and their callbacks) answers which rows a filter shows, which selection still exists, which row 开始复核 opens and whether a row can be marked; `LyricPlaybackControls` (state, whether the player holds this project, seek and toggle) answers whether this project is playing, which row is at the playhead and where the paused playhead is for a split. The content's constructor went from 26 to 15 arguments, and the rules have plain unit tests. The screen builds the review group in `_reviewControls`, so it stays under its 1200-line budget. E-06: the theme's `labelSmall` was 10 px; it is now 11, and small badges no longer shrink their label to 10 (they keep tighter padding and a smaller icon). S-05: the last two literal sizes, the 24 px avatars in the download manager and the remote library, use the new `AppSpacing.avatarRadius`.
- Files:
  - New: `lib/features/lyrics/presentation/widgets/lyric_editor_review_controls.dart`, `test/features/lyrics/presentation/widgets/lyric_editor_review_controls_test.dart`, `test/core/theme/text_theme_floor_test.dart`.
  - `lib/features/lyrics/presentation/widgets/lyric_editor_content.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`.
  - `lib/core/theme/app_theme.dart`, `lib/core/theme/spacing_tokens.dart`, `lib/core/widgets/app_badge.dart`, `test/core/widgets/app_badge_test.dart`.
  - `lib/features/transfer/presentation/screens/mobile_download_manager_screen.dart`, `lib/features/transfer/presentation/screens/mobile_remote_music_library_screen.dart`.
  - `test/architecture/source_hygiene_test.dart` (also rejects `radius: <number>`).
  - `artifacts/ui-audit/reports/issues.md` (status section for round 14).
- Validation:
  - The editor's widget tests (save, review, split, playback) exercise the content through the screen; the moved rules are also covered directly.
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - `_reviewControls` reads the selection from the controller rather than the selector record; the selector still lists it, so the content rebuilds when the selection changes.
  - 11 px text and the slightly taller small badges have not been looked at in a running app.
- Commit: `Group the editor's review and playback inputs`
