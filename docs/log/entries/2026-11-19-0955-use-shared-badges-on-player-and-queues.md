# [2026-11-19 09:55] Use shared badges on player and queue screens

- Scope: UI/UX audit C-05, second slice. The remaining badge copies in Now Playing, quick play, the playback queue, project detail and the transcription queue now delegate to `AppBadge`. Two fixes to the shared widget came out of these call sites: neutral badges use the translucent `hoverOverlay` wash instead of `bgSurface` (the player and project cards are `bgSurface` or the card gradient, where a surface badge would vanish), and the icon is laid out inside the label text as a `WidgetSpan`, so the badge works directly inside a `Row` (unbounded width) as well as in bounded parents where long labels end with an ellipsis.
- Files:
  - `lib/core/widgets/app_badge.dart` (neutral wash, icon inside the text) and `test/core/widgets/app_badge_test.dart` (wash colour, icon badge inside a `Row`).
  - `now_playing_screen.dart` and `quick_play_screen.dart` (`_InfoChip`, bold neutral), `playback_queue_panel.dart` (`_CurrentBadge`, bold accent), `project_detail_screen.dart` (`_StatusPill`, `_MiniPill`, `_MetricChip`), `transcription_queue_panel.dart` (`_CountPill`, `_StatusBadge`).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Line lengths were measured for the tall-style formatter. Existing tests were searched for lookups of the migrated labels: none match icon badges by exact text (their plain text now starts with the icon placeholder), and plain badges still match `find.text`.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: the hoverOverlay wash renders about #3E3E3E on cards (the old `bgHighlight` of the player chips) and about #2A2A2A on the page; secondary text stays above 5:1 on both. Transcription count pills are 2 px shorter (padding 8/4 instead of 9/6), and the project-detail metric chips gain the wash instead of the flat surface.
  - After this slice no private badge implementation is left; `_StagePill` (project step indicator, medium radius) and `_WordChip` (interactive word timing chip) are different components and stay as they are.
- Commit: `Use shared badges on player and queue screens`
