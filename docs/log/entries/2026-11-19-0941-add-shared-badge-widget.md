# [2026-11-19 09:41] Add a shared badge widget

- Scope: UI/UX audit C-05, first slice. Status and metadata pills were rebuilt per screen with different paddings (6/2 to 9/6), background alphas (16 to 28), icon sizes (13 or 14) and label sizes. `AppBadge` in `lib/core/widgets/` gives them one shape: a tone enum (neutral, accent, success, warning, error, info), an optional explicit colour for callers that already map a status to a colour, an optional icon, a `small` size for dense rows and an `emphasized` bold label. Neutral badges sit on `bgSurface` with secondary text; tinted badges use the colour at alpha 24 behind text in the full colour. Labels stay on one line with an ellipsis instead of overflowing.
- Files:
  - `lib/core/widgets/app_badge.dart` (new) and `test/core/widgets/app_badge_test.dart` (new: neutral and tinted colours, colour override, small size, tone map, ellipsis in a narrow parent).
  - Migrated, keeping the private wrapper names and call sites: `dashboard_screen.dart` (`_MetaChip`), `import_audio_screen.dart` (`_FeaturePill`), `review_inbox_screen.dart` (`_Badge`), `reference_alignment_review.dart` (`_Badge`, small), `lyric_editor_atoms.dart` (public `LyricTinyBadge`, small; its theme imports are no longer needed).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Line lengths were measured so the tall-style formatter's joins and splits are already applied.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart` (verified to reproduce main with zero diff).
- Notes:
  - Visible changes: neutral `LyricTinyBadge` labels move from a grey tint with tertiary text to the surface colour with secondary text (higher contrast). The dashboard and import pills keep their look within a pixel of padding; the import pill icon is now 4 px from its label instead of 6.
  - Not yet migrated: the player, project and transcription badges (next slice). `_StagePill` in the project screen is a step indicator with a medium radius, not a badge, and stays separate.
- Commit: `Add a shared badge widget`
