# [2026-10-19 15:17] 修复 ASR 模型下载超时与自动续传

- Scope: 为 Whisper 与 Qwen 模型下载增加连接/无数据超时；将 Whisper 网络中断转换为可自动重试的错误，保留 `.part` 断点并验证 Range 响应，避免下载失败后长期等待或丢失已下载内容。
- Files: `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`, `lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart`, `test/features/transcription/retrying_asr_runtime_manager_test.dart`, `test/features/transcription/asr_runtime_resume_contract_test.dart`, `docs/asr_runtime_installation.md`, `docs/work_log.md`
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/transcription/data/services/managed_asr_runtime_manager.dart lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart test/features/transcription/retrying_asr_runtime_manager_test.dart test/features/transcription/asr_runtime_resume_contract_test.dart` => success；仅有 6 条既存 info，无错误/警告
  - ASR 下载、重试、续传、完整性相关 6 组定向测试 => success
  - `git diff --check` => success
  - `flutter analyze --no-fatal-infos` => 未通过；存在未修改文件 `test/features/player/fullscreen_ktv_interaction_surface_test.dart` 对 `WidgetTester.doubleTap` 的既有错误
- Notes: 网络可用但短暂中断时最多自动重试 4 次；若 Hugging Face 持续不可达，错误会显示且稍后可从保留的断点继续。当前未对真实 Hugging Face 网络做端到端下载验证。
- Commit: `Retry stalled ASR model downloads`
