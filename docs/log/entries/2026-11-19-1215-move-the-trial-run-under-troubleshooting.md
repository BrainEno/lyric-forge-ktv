# [2026-11-19 12:15] Move the trial run under troubleshooting

- Scope: UI/UX audit SE-05 and SE-01. Settings showed a developer smoke test (真实音频端到端自检, explained in terms of runtime, production ASR and pipelines) between the recognition settings and diagnostics, as if it were a setting, and the navigation tooltip promised 播放、识别与存储设置 although the page only holds recognition and diagnostics. The page now has two labelled groups, AI 识别 and 故障排查 (diagnostics first, then the trial run). The card is now 试识别一首歌, built on `SettingsSectionCard`, and says in plain words what it does and that it does not prove the lyrics are accurate. The tooltip says 识别环境、诊断与试识别.
- Files:
  - `lib/features/settings/presentation/widgets/asr_end_to_end_smoke_test_card.dart` (user-facing copy, `SettingsSectionCard`, tonal button, `pickAudio` and `desktopSupported` overrides, `lastRunSummary`).
  - `lib/features/settings/presentation/screens/settings_screen.dart` (`settingsIntro`, `SettingsGroupLabel`, order).
  - `lib/core/navigation/app_destinations.dart` (settings description).
  - Test: `test/features/settings/asr_end_to_end_smoke_test_card_test.dart` (new: no jargon, disabled with a reason off Windows/macOS, run → progress → cancel → opens `/project/p1/lyrics`, last-run summary, failure text, cancelled picker, empty path; source check for the group order; tooltip no longer promises playback or storage).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. The injection contract (`required this.smokeTestService`, no `AppServices.instance`) still holds.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Progress messages and error texts that come from the smoke-test service itself (and the generated project's `· ASR 自检` suffix) are unchanged; the card's own copy no longer says so, to avoid promising a name it does not control.
- Commit: `Move the trial run under troubleshooting`
