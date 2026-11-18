# Handoff

## 目标

用户要求：清理 open 的 issue，先核实描述的问题是否真实、合理，再修复真实有效的（D-028）。

- **#460**：空 `catch` 全部改为共享写入队列 `SerialWriteQueue` 或带日志的 `bestEffort`；打点窗口在播放器拒绝命令时给出提示。
- **#458**：最后一个颜色字面量改为主题 token。
- **#461**：ASR 下载地址集中到 `AsrEndpoints`，发布仓库可通过 `--dart-define` 覆盖。
- **#462**：三个安装器共用 `ResumableFileDownload`（续传校验、大小校验、逐块取消）。
- **#464**：删除没有入口的 `RemoteMediaLibraryScreen`，桌面传输中心去掉 `v2`，在 `media_hub_plan.md` 写明页面职责。
- 核实后不需要再改：#442、#319（已实现）、#416（大部分已修好）。#413、#260、#258、#226 是较大的功能需求，本轮不做。

合并前先征求用户确认。

## Git 现场

- 分支：`arena/61f424ad-lyric-forge-ktv`，基于 main `80b04a341c817fa3463645fe8d53b08a5ddf4610`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **core**：`persistence/serial_write_queue.dart`、`diagnostics/best_effort.dart`（新）；`theme/color_tokens.dart`、`app_diagnostics.dart`、`app_logger.dart`、`atomic_json_file.dart`。
- **transcription**：`asr_endpoints.dart`、`resumable_file_download.dart`（新）；三个 runtime manager、连接检查、HTTP client 工厂、FFmpeg 发布表、进程管理、存储服务、批量队列。
- **player / project / transfer**：九个文件存储、KTV 录音和麦克风、Media Hub 服务和手机端页面；删除 `remote_media_library_screen.dart`、`remote_media_library_dependencies.dart`，重命名桌面传输中心。
- **lyrics**：打点窗口和控件（`LyricTapTransportFeedback`）、逐字时间编辑、编辑页。
- **测试**：5 个新测试文件（含 `test/architecture/source_hygiene_test.dart`），四个下载相关契约测试改为检查共享下载器。
- **文档**：`decisions.md`（D-028）、`media_hub_plan.md`、工作日志条目 `2026-11-24-1200`、本文件。

## 检查结果

临时 workflow（run 44309849609）：`dart format` 无改动；`flutter analyze` 0 个错误/警告，186 条 info（与 main 相同）；定向测试 282 个通过；全量 2789 个通过、2 个跳过、0 个失败（改动前 2758 个）；工作日志检查通过。

## 下一步

- 在真实网络下各装一次 Whisper 模型、Qwen 模型和 FFmpeg，中途断网再续传，确认提示和续传正常。
- 打开详细诊断后看一遍新出现的 debug/warning 日志，如果某条太吵可以调成 housekeeping。
- #416 剩下的小问题：可以补一个 800×480 下复核对话框的布局测试。
- #413（识别质量语料库）仍未开始。

## 已知风险

- 以前静默的失败现在会写日志，诊断报告可能多出一些 warning。
- `ResilientAsrRuntimeManager` 现在会拒绝不一致的续传响应；遇到不支持 Range 的镜像时会删掉 `.part` 重新下载。

最后更新：2026-11-24 12:00（Asia/Taipei）
