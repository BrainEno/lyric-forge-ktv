# [2026-11-19 11:55] Add a button spinner that follows the label

- Scope: residual hard-coded white from the round 2 contrast pass. Three busy buttons (加入转写队列, 一键准备识别环境, 生成歌词) drew an 18 px spinner in fixed white. They are disabled while busy, so the white spinner was brighter than their dimmed label, and on the accent fill white is only 2.6:1. `AppButtonSpinner` takes the button's resolved icon colour instead. The two error-filled controls (恢复并覆盖, KTV record/stop) now use a named `AppColors.onError` token (white, 4.7:1 on `error`), which also backs the colour scheme's `onError`.
- Files:
  - `lib/core/widgets/app_button_spinner.dart` (new).
  - `lib/features/import/presentation/screens/import_audio_screen.dart`, `lib/features/import/presentation/screens/transcription_ready_import_screen.dart`, `lib/features/project/presentation/screens/project_detail_screen.dart` (spinners).
  - `lib/core/theme/color_tokens.dart`, `lib/core/theme/app_theme.dart` (`onError`).
  - `lib/features/lyrics/presentation/widgets/reference_alignment_backup_dialog.dart`, `lib/features/player/presentation/widgets/ktv_recording_toolbar.dart` (error foregrounds).
  - Test: `test/core/widgets/app_button_spinner_test.dart` (new: black on an enabled accent button, translucent when disabled, ambient icon colour and custom size outside buttons).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. No existing test looks for these spinners.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - White that remains on purpose: the round play buttons (white disc, black icon) in the player bars and `TransportBar`, the KTV lyric base colour, the quick-play waveform thumb, the QR scanner overlay and the transfer hub QR card.
  - This commit touches 10 files (one over the usual 8) because the spinner and the token each have three or more call sites; the change per file is a few lines.
- Commit: `Add a button spinner that follows the label`
