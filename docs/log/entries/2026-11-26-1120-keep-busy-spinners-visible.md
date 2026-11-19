# [2026-11-26 11:20] Keep busy spinners visible

- Scope: Round 9 contrast feedback, continued from the lavender buttons. Busy buttons hard-coded their spinners: the default accent spinner on a lavender fill, and black spinners on play discs whose disabled state was transparent (desktop player bar, 1.1:1) or #535353 (mobile bar and transport, 2.7:1). The busy buttons now use `AppButtonSpinner`, which takes the button's icon colour. Filled and tonal buttons get a readable disabled grey (`AppTheme.disabledFill` / `disabledForeground`: #8F8F8F on #3E3E3E, 3.3:1, instead of white at 38 % on white at 12 %, 2.2:1). The three play discs share `AppTheme.playDisc`, which stays light grey under a black spinner while playback loads (10:1). The dashboard play button keeps its accent disc while buffering (`AppTheme.busyAccentDisc`, 9.2:1) instead of turning into the grey of an unavailable control.
- Files:
  - `lib/core/theme/app_theme.dart` (`disabledFill`, `disabledForeground`, `playDisc`, `busyAccentDisc`; filled button theme).
  - Busy buttons: `dashboard_now_playing.dart`, `reference_alignment_dialog.dart`, `ktv_microphone_sheet.dart`, `ktv_take_result_sheet.dart`, `local_media_metadata_dialog.dart`, `diagnostics_settings_card.dart`, `transcription_config_dialog.dart`, `desktop_media_transfer_hub_screen.dart`, `mobile_remote_music_library_screen.dart`.
  - Play discs: `global_player_bar.dart`, `mobile_global_player_bar.dart`, `transport_bar.dart`.
  - `test/core/theme/busy_button_contrast_test.dart` (new), `test/core/widgets/app_button_spinner_test.dart`.
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Page-level loading spinners (empty lists, dialogs while loading) keep the accent, which reads at 6.5:1 or more on every surface.
  - The spinner in `asr_existing_model_actions.dart` is a status icon beside a scan summary, not a button icon, and keeps the accent.
- Commit: `Keep busy spinners visible`
