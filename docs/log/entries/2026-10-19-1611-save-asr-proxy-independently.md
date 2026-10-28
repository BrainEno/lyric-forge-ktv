# [2026-10-19 16:11] 允许代理独立保存并在对话框内提示缺项

- Scope: 将下载代理持久化拆成独立操作；高级设置中的识别模型/路径不完整时仍可保存代理并退出，重新打开时恢复代理。缺少的识别项在高级设置窗口内实时提示，不再用主界面提示或配置完整性校验阻断代理保存。
- Files: `lib/features/transcription/domain/services/transcription_settings_store.dart`, `lib/features/transcription/data/services/file_transcription_settings_store.dart`, `lib/core/services/service_locator.dart`, `lib/features/transcription/presentation/widgets/transcription_config_dialog.dart`, `lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart`, `lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart`, `test/features/transcription/file_transcription_settings_store_test.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - 设置存储、代理保存、配置合同、环境预检及队列恢复定向测试（6 个测试文件）=> All tests passed
  - `flutter analyze --no-fatal-infos`（本次涉及的 8 个 Dart 文件）=> success；6 条既存 info，无错误/警告
  - `dart format --output=none --set-exit-if-changed`（本次涉及的 Dart 文件）=> success
  - `git diff --check` => success
- Notes: 代理写入现有 transcription settings JSON 的独立字段；部分配置不会被常规 `load()` 当作可运行识别配置返回，因此不影响环境预检或实际转录。成功保存完整配置时仍沿用原有完整配置保存流程。
- Commit: `Allow saving ASR proxy independently`
