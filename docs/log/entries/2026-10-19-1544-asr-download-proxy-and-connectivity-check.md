# [2026-10-19 15:44] 为 ASR 模型下载接入代理与连通性检查

- Scope: ASR 下载统一使用代理客户端工厂，依次检查手动 HTTP 代理、环境代理、Windows/macOS 静态系统代理并在无配置时直连；增加 Hugging Face 模型源测试按钮，将代理随识别配置保存，并为请求、响应体和下载流设置超时。进度 UI 仍分别呈现整体环境准备与单文件下载状态。
- Files: `lib/features/transcription/data/services/asr_download_http_client_factory.dart`, `lib/features/transcription/data/services/asr_download_connection_checker.dart`, `lib/features/transcription/domain/services/asr_download_connection_checker.dart`, `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`, `lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart`, `lib/features/transcription/data/services/resilient_asr_runtime_manager.dart`, `lib/features/transcription/domain/models/transcription_models.dart`, `lib/features/transcription/presentation/widgets/transcription_config_dialog.dart`, `lib/core/services/service_locator.dart`, `test/features/transcription/asr_download_http_client_factory_test.dart`, `test/transcription_config_test.dart`, `test/features/transcription/asr_runtime_resume_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - ASR 代理、配置、续传、进度、模型完整性及重试定向测试（6 个测试文件）=> All tests passed
  - `flutter analyze --no-fatal-infos`（本次变更涉及文件）=> success；13 条 info，无错误/警告
  - `dart format --output=none --set-exit-if-changed`（代理工厂、连通性实现及配置/代理测试）=> success
  - `git diff --check` => success
  - `flutter analyze --no-fatal-infos`（全项目）=> 被既有错误阻断：`fullscreen_ktv_interaction_surface_test.dart` 调用了不存在的 `WidgetTester.doubleTap`
- Notes: 代理仅支持无认证 HTTP 地址；不支持 SOCKS 与 PAC/WPAD 自动配置，检测到可识别的 PAC 设置时会提示手动填写。Linux 目前读取代理环境变量，不解析桌面系统代理。未使用第三方镜像；尚未对真实 Hugging Face 网络及系统代理进行端到端下载验证。
- Commit: `Add proxy support for ASR downloads`
