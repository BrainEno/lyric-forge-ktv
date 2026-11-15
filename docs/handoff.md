# Handoff

## 目标

实现 #233（统一日志、崩溃接管与可导出的诊断包）和 #226 中可以在代码里完成的部分：KTV 录音/导出与歌词识别的实测耗时、实时倍率与内存峰值采集，端到端延迟与长歌基准的测量流程文档，以及 KTV 麦克风面板上的数据来源说明。真实设备上的数值仍需按文档采集。PR 关闭 #233，并关联 #226（不关闭，设备测量未完成）；合并前先征求用户确认。

## Git 现场

- 分支：`arena/2cce7c3d-lyric-forge-ktv`，基于 main `247139233c86a52acdf4a31291719bcc5ecc6ff1`。
- 验证用的临时 workflow 和它提交的结果文件在开 PR 前删除，不进入 PR diff。

## 已改文件

- **诊断核心（`lib/core/diagnostics/`）**
  - `log_record.dart`、`log_redactor.dart`、`app_logger.dart`：分级日志，唯一脱敏点，内存与控制台 sink。
  - `file_log_sink.dart`：JSON Lines 文件日志，512 KB 轮转。
  - `crash_capture.dart`：`FlutterError.onError` / `PlatformDispatcher.onError` 接管与崩溃摘要存储。
  - `operation_timings.dart`、`process_memory.dart`：耗时样本、实时倍率、RSS。
  - `app_build_info.dart`、`diagnostics_report.dart`、`app_diagnostics.dart`：版本与平台、诊断包、门面与偏好。
- **装配**：`lib/app/diagnostics_assembly.dart`（目录与功能分区：识别环境、KTV 麦克风、资料库规模）；`app_services.dart` 先建 `diagnostics`，用 `TimedTranscriptionService` / `TimedKtvRecordingService` 包住最外层服务；`transcription_assembly.dart` 把 `diagnostics` 交给设置页；`main.dart` 启动诊断。
- **计时装饰器**：`features/transcription/data/services/timed_transcription_service.dart`（含 WAV 头时长解析）、`features/player/data/services/timed_ktv_recording_service.dart`。
- **界面**：设置页新增「诊断与日志」卡片（导出、复制、清除、详细日志、崩溃记录开关、耗时列表）；KTV 麦克风面板在延迟数值下方说明数据来源与局限。
- **调用点替换**：`quick_play_screen.dart`、`file_project_repository.dart`、`main.dart` 的 `debugPrint` / `developer.log` 改为 `appLog`。
- **文档**：`docs/diagnostics.md`（组成、脱敏规则、诊断包内容、实测流程）、`decisions.md`（D-016）、本文件、工作日志条目 `2026-11-15-2100`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。各次运行见工作日志条目。

## 下一步

- 按 `docs/diagnostics.md` 的回环流程，在 Windows、macOS、Android 各一台设备上测 KTV 端到端延迟，并把结果写入 `docs/benchmarks/`。完成后才能关闭 #226。
- 用 5、8、12 分钟的歌各跑一次识别和混音导出，记录 RTF 与 `peakRssMb`。Whisper 子进程的内存要单独测。
- 其余模块逐步把日志迁到 `appLog`（转写、传输、媒体中心），并只记元数据。

## 已知风险

- 脱敏基于模式匹配，不认识的密钥格式（比如没有键名的裸令牌）不会被替换。诊断包导出前可读，用户可以检查。
- `peakRssMb` 不包含 `whisper-cli`、FFmpeg 子进程。
- `appVersion` 是手写常量，改版本号时必须同步，否则测试失败（这是有意设计的）。
- 崩溃处理器在 `AppServices.initialize()` 之后才装上，初始化过程中的同步异常仍由 Flutter 默认处理。

最后更新：2026-11-15 21:00（Asia/Taipei）
