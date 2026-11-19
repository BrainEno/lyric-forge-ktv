# [2026-11-19 11:45] Move the library transfer button into the section strip

- Scope: UI/UX audit L-01 and L-03. On compact and medium widths the music library opened 跨设备传输 from a `FloatingActionButton.small`: 40 dp, under the 48 dp target in AGENTS.md, and floating over the last rows of every section. The strip's tonal icon button, which wide layouts already had, now shows at every width with a 48 dp minimum on touch and narrow windows, and the floating button is gone. Selected chips app-wide get an accent outline and a 16 % accent tint (`AppColors.accentMuted`) instead of the default grey fill alone, so the active library section, filter or mode is clear at a glance.
- Files:
  - `lib/features/player/presentation/screens/local_music_library_shell.dart` (no FAB; strip transfer button at every width, `transferButtonKey`).
  - `lib/core/theme/color_tokens.dart` (`accentMuted`).
  - `lib/core/theme/app_theme.dart` (`chipTheme`, `AppTheme.chipSide`).
  - Tests: `test/features/player/presentation/screens/local_music_library_shell_test.dart` (no FAB, 48 dp button in the strip row on compact, at the strip end on wide, opens the transfer route); `test/core/theme/chip_theme_test.dart` (new: theme values, white-on-tint contrast above 7:1, outline drawn on a real `ChoiceChip`).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - White on the tint over `bgElevated` computes to 13.8:1.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The chip theme reaches all 20 `ChoiceChip`s (lyric dialogs, player modes, take results, remote library). None of them sets its own side or selected colour.
  - L-02 (four transfer entries across the app) is not addressed here.
- Commit: `Move the library transfer button into the section strip`
