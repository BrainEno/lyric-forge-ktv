# Handoff

## 目标

自选开发任务（#467 之后，D-026）：

- **重新识别这一段**：校对菜单新增，只把选中的几行（可向前后延伸，或延伸到相邻行）剪成片段，用 Qwen3-ASR 或 Whisper 重新识别并替换，或者保留文字只重新对齐时间。结果预览后作为一次可撤销修改应用。
- **参考对齐接受零时长的词**：`ForcedAlignmentHttpClient` 不再因为对齐器放不下的词（零时长）让整个请求失败，改用 `AlignerWordTimingRepair.repairToTimedSpans` 修复；智能校对 V2 的 ForcedAligner 选项在有反复和声的歌上也能用。
- #465：`pubspec.yaml` 中 `flutter_soloud` 注释的 Flutter 版本说明。

合并前先征求用户确认。

## Git 现场

- 分支：`arena/f9362eba-lyric-forge-ktv`，基于 main `b98c0ca3b40120c793575911dc82561b759a1c28`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域**：`lyrics/domain/services/lyric_span_rerecognition.dart`（新）：范围、替换、重新对齐的计划，以及 `LyricSpanRecognizer` 接口。
- **数据**：`transcription/data/services/project_span_recognition_service.dart`（新）：FFmpeg 剪片段、运行时检查、资源租约、取消；`asr_resource_coordinator.dart` 新增 `spanRecognition`。
- **界面**：`lyric_span_recognition_dialog.dart`（新）；菜单、工具栏、协调器、`LyricEditorDependencies.spanRecognizer`、`lyric_editor_assembly.dart` 接入；漏唱和声检查的说明改为指向新工具。
- **对齐**：`aligner_word_timing_repair.dart`（`repairToTimedSpans`）、`forced_alignment_http_client.dart`。
- **文档**：`decisions.md`（D-026）、`high_quality_asr.md`、工作日志条目 `2026-11-22-1200`、本文件。

## 检查结果

见 PR 描述（临时 workflow 的格式、静态分析、定向测试、全量测试、工作日志检查结果）。

## 下一步

- 用真实歌曲试用“重新识别这一段”：片段边缘的词是否被截断或重复，默认 0.5 秒延伸是否合适。
- 可以考虑在识别循环检查、漏唱和声检查的每一项上直接提供“重新识别这一段”的入口（目前需要先选中行再从菜单打开）。
- #413（识别质量语料库与回归门槛）仍未开始，需要团队确认语料和门槛。

## 已知风险

- 合并进相邻词的零时长词没有自己的时间，逐字时间按合并后的词计算。
- 重新识别替换选中的行时会覆盖其中手动编辑过的行（对话框会提示数量）。
- Qwen 重新识别使用应用共享的 Qwen 服务；取消会让该服务重启会话，下一次识别需要重新加载模型。

最后更新：2026-11-22 12:00（Asia/Taipei）
