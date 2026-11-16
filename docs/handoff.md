# Handoff

## 目标

让识别得到的逐字时间真正用起来，并新增一个识别循环检查：

- 保留 Qwen3 ForcedAligner 的逐词时间（`LyricLine.words`），编辑、平移、打轴后仍然有效。逐字 LRC 和 ASS 优先使用真实逐字时间，拆分行时按词分界。检查器可以查看逐词时间。
- 「校对」菜单新增“识别循环检查”：找出一行内同一句反复十几遍、连续多行完全相同的识别循环，预览后删减。识别摘要卡新增“识别循环 N 行”提示。

所有改动都是可撤销的编辑，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/01574735-lyric-forge-ktv`，基于 main `f56b824c61ce256d0bdc9c61d78438f9f517d4be`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **数据模型**：`project/domain/models/lyric_document.dart` 新增 `LyricWordTiming` 和 `LyricLine.words`，JSON 键为 `words`（可选）。
- **转写**：`qwen3_asr_native_transcription_service.dart` 分组时保留逐词时间，也读取段内嵌套的 `words` / `tokens`；`resumable_chunked_transcription_service.dart` 把逐词时间和行一起加上分段偏移。
- **领域服务（`lib/features/lyrics/domain/services/`）**
  - `lyric_word_timing_service.dart`（新）：按演唱字符匹配，计算每个字的时间（行被移动后线性映射），以及切片和归一化。
  - `lyric_asr_loop_detector.dart`（新）：检测行内循环和连续重复行，生成修复计划。
  - `lyric_karaoke_timing_service.dart`：`syllables` 新增 `characterStarts` 参数。
  - `lyric_export_encoder.dart`：`LyricExportCue.characterStarts`，逐字 LRC 和 ASS 优先使用真实逐字时间。
  - `lyric_line_structure_service.dart`：拆分新增 `wordTiming` 分界来源，拆分和合并都会带上逐字时间。
  - `lyric_draft_health_service.dart`：新增 `loopRows`。
- **界面**
  - `widgets/lyric_asr_loop_dialog.dart`（新）、`widgets/lyric_word_timing_strip.dart`（新）。
  - `lyric_batch_text_edit.dart`（`asrLoopCheck`）、`lyric_batch_text_tools_coordinator.dart`、`lyric_proofread_menu_button.dart`、`lyric_editor_toolbar.dart`、`lyric_editor_content.dart`、`lyric_recognition_summary_card.dart`。
  - `lyric_export_dialog.dart`（显示真实逐字时间的行数）、`lyric_inspector_pane.dart`（逐词时间）、`lyric_editor_document_controller.dart`（拆分提示）。
- **文档**：`decisions.md`（D-021）、本文件、工作日志条目 `2026-11-18-1200`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。

- `dart format`：改动文件已格式化。
- `flutter analyze`：没有 error 或 warning，186 条 info，与 main 相同。
- 目标测试 12 个文件，153 个测试全部通过。
- `flutter test` 全量：2555 通过，2 跳过，0 失败（main 为 2516 通过）。
- `dart tool/work_log.dart write` 和 `check`：通过（唯一的 warning 是旧条目的问题，早已存在）。
- `lyric_editor_screen.dart`：仍为 1178 行。

## 下一步

- 用 #413 的真实歌曲语料校准循环阈值（行内 4/6 遍、单字 8/12 遍、跨行 4/6 行）。
- 逐字打轴：在 `LyricTapSyncSession` 上扩展为每个字按一次，结果直接写入 `LyricLine.words`。
- Whisper 路径可以开启 word timestamps，同样写入 `words`。
- 行内循环删减后，可以把保留部分的逐字时间切出来，而不是让整行失效。

## 已知风险

- 旧版本应用打开新工程会忽略 `words`，再保存时会丢掉逐字时间（行级时间不受影响）。
- 循环检查会把歌曲本身的大量重复（如“啦”连唱很多遍）当成疑似循环；这类只列出、不默认勾选，也可以撤销。
- 逐字时间按演唱字符数匹配；文字改动后字数不变但内容错位（例如调换顺序）时，逐字时间仍会被使用。

最后更新：2026-11-18 12:00（Asia/Taipei）
