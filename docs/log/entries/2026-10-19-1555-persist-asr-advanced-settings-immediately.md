# [2026-10-19 15:55] 立即持久化安装流程中的高级识别设置

- Scope: 在首次环境准备/批量导入的安装弹窗中，用户从高级设置确认代理或其他识别配置后立即保存到共享本地设置存储，不再等到外层弹窗完成；持久化失败时在弹窗内明确提示，避免用户重试时误以为配置已保存。
- Files: `lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `docs/work_log.md`
- Validation:
  - `flutter test test/features/transcription/asr_install_experience_contract_test.dart test/features/settings/transcription_settings_contract_test.dart test/transcription_config_test.dart` => All tests passed
  - `flutter analyze --no-fatal-infos lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart test/features/transcription/asr_install_experience_contract_test.dart` => No issues found
  - `git diff --check` => success
- Notes: 配置在高级设置对话框确认后先写入持久化存储，再应用到当前安装流程；下载中断后的重试和之后重新打开环境准备都会读取该代理。未改变取消高级设置时的行为。
- Commit: `Persist ASR advanced settings immediately`
