# Handoff

## 目标

在没有参考歌词的情况下，减少识别后校对中的重复劳动。「校对」菜单新增三个批量文字工具：批量查找替换、重复段落一致性检查、清理识别文本。质量报告新增两项对应指标。这些工具只改文字，先预览，作为一次可撤销修改写入编辑中的文档，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/545e77c0-lyric-forge-ktv`，基于 main `2c9b1f6f11b454fec42755a9d4d2dabf0557cc47`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域服务（`lib/features/lyrics/domain/services/`）**
  - `lyric_find_replace_service.dart`：全文查找替换。可忽略简繁差异和英文大小写，可选英文全词匹配；匹配范围按 UTF-16 偏移给出；受保护行默认跳过。
  - `lyric_repetition_consistency_service.dart`：近似重复行分组（字形折叠的比较键加带宽限制的编辑距离，以多数写法为种子聚类），按「手动确认 → 多数 → 置信度」给出推荐，并给出是否预选的判断。
  - `lyric_text_cleanup_service.dart`：9 条可开关的清理规则，以及字幕水印、纯标注行的识别；删除整行时平移行索引类证据。
- **界面**
  - `widgets/lyric_batch_text_edit.dart`：`LyricBatchTextTool`、结果类型 `LyricBatchTextEdit`、共用对话框框架（小窗口和大字号下可滚动）、预览行（高亮、逐行勾选）。
  - `widgets/lyric_find_replace_dialog.dart`、`lyric_repetition_consistency_dialog.dart`、`lyric_text_cleanup_dialog.dart`。
  - `controllers/lyric_batch_text_tools_coordinator.dart`：负责弹窗顺序和过期文档检查，通过 `LyricEditorProofreadFlowHost.applyProofreadDocument(markManuallyEditedLineIds:)` 应用结果。
  - 菜单、工具栏、编辑器内容、快捷键：Ctrl+H 打开查找替换，macOS 上为 Cmd+Shift+H。编辑器屏幕只传一个 `onBatchTextTool`，保持在 1200 行的编排预算以内。
  - `lyric_editor_document_controller.dart`：`replaceDocument` 可以把用户选定文字的行加入手动编辑标记，撤销时一并恢复。
- **工具**：`tool/asr_quality_report.dart` 新增 `asrBoilerplateLineCount`、`repetitionInconsistentLineCount`。
- **文档**：`decisions.md`（D-017）、本文件、工作日志条目 `2026-11-16-0900`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。

- `flutter analyze`：没有 error 或 warning，186 条 info，与基线相同。
- `flutter test` 全量：2369 通过，2 跳过，0 失败（运行 43798504706；基线为 2312 通过）。
- `dart tool/work_log.dart check`：通过。

## 下一步

- 用真实识别结果试用三个工具，补充字幕水印与标注词表（`LyricTextCleanupService.asrBoilerplateFragments` / `annotationWords`）。
- 在 #413 的真实歌曲基线里，记录两项新指标，作为识别管线改进的观察项。
- 可以考虑在识别落盘时自动去掉字幕水印行（这次只放在编辑器中，由用户确认）。

## 已知风险

- 重复行检查只依据歌词文本。两种写法都反复出现时不预选，但推荐写法仍可能出错，需要试听确认。
- 清理规则面向卡拉 OK 显示惯例（句中标点改空格）。如果用户需要保留标点，可以逐条关闭。
- 查找替换没有正则模式；面向的是「同一个词识别错多次」的场景。

最后更新：2026-11-16 09:00（Asia/Taipei）
