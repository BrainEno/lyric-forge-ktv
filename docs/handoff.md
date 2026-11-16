# Handoff

## 目标

解决识别稿的断行问题：识别器按停顿切分，常把两句歌词并成一行，或从一句里切出一两个字的碎片。

- 编辑器新增逐行“拆分 / 合并”。
- 「校对」菜单新增批量工具“整理断行”。
- 识别摘要卡新增“可批量整理”提示，一键打开对应工具。
- 质量报告新增两项结构指标。

所有改动都是可撤销的编辑，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/e1b625f0-lyric-forge-ktv`，基于 main `406c785fd6f34e77ad5c5ad4ec15cb6cc697f062`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域服务（`lib/features/lyrics/domain/services/`）**
  - `lyric_line_structure_service.dart`：拆分与合并。
    - 自然断点选择、演唱权重。
    - 分界时间：优先取暂停位置，否则按字数比例；两半各至少 0.2 秒。
    - 合并后的文字拼接、时间范围、置信度。
  - `lyric_structure_advisor.dart`：批量建议（过长行拆分、碎片行合并）及一次性应用（`LyricStructurePlan.applyTo`），会平移行索引类证据并为新行分配 id。
  - `lyric_draft_health_service.dart`：识别稿的机械问题计数（字幕水印/标注行、重复句写法不一、过长行、碎片行），按文档实例缓存。
  - `lyric_indexed_review_metadata.dart`：新增 `afterRowSplit`、`afterRowsMerged`、`remapped`。
- **界面**
  - `controllers/lyric_editor_document_controller.dart`：`splitLine`、`mergeLineWithNext`。两者都是一次撤销步骤，结果行加入手动编辑标记，并调整选中行。
  - `widgets/lyric_inspector_pane.dart`：新增“拆分此行”和“与下一行合并”按钮（`LineStructureActions`）。在文本框里按 Ctrl+Enter（macOS 为 Cmd+Enter）从光标处拆分。
  - `widgets/lyric_list_pane.dart`：右键菜单新增“从中间断点拆分为两行”和“与下一行合并”。
  - `widgets/lyric_editor_content.dart`：只有本工程的音频处于暂停状态时，才把播放头位置作为分界传给拆分。小屏的检查器底部弹窗在结构编辑后自动关闭。
  - `widgets/lyric_structure_dialog.dart`、`lyric_batch_text_edit.dart`（`LyricBatchTextTool.lineStructure`）、`lyric_batch_text_tools_coordinator.dart`、菜单、工具栏。
  - `widgets/lyric_recognition_summary_card.dart`：“可批量整理”提示。
  - `screens/lyric_editor_screen.dart`：行编辑的收尾逻辑合并为 `_applyRowEdit`；复核后跳转直接使用已排序的队列。共 1198 行，预算为 1200 行。
- **工具**：`tool/asr_quality_report.dart` 新增 `overlongLineCount`、`fragmentLineCount`。
- **文档**：`decisions.md`（D-018）、本文件、工作日志条目 `2026-11-16-1230`。

## 检查结果

全部来自 GitHub Actions 临时 workflow，沙箱里没有 Dart/Flutter 工具链。

- `flutter analyze`：没有 error 或 warning，186 条 info，与基线相同。
- `flutter test` 全量：2429 通过，2 跳过，0 失败（运行 43804942749；基线为 2369 通过）。前两轮发现的两个问题都出在测试代码里：缺少一个 import；右键菜单测试的查找方式不对。两处都已修正。
- `dart tool/work_log.dart check`：通过。

## 下一步

- 用 #413 的真实歌曲基线校准阈值：过长 20、碎片 2 个字或 0.7 秒、合并间隔 0.35 秒。记录 `overlongLineCount` 和 `fragmentLineCount`。
- 可以考虑让拆分直接利用词级时间戳（如果引擎提供），而不是按字数比例估算。
- 可以考虑在识别落盘时自动去掉字幕水印行（目前仍由用户在编辑器里确认）。

## 已知风险

- 按字数比例估算的分界时间只是起点。拖长音、间奏前后误差会比较大，需要试听后微调。提示文案已经说明这一点。
- 没有空格或标点的长行只能从中间拆分，这类建议默认不勾选。
- 被拆分或合并的行会加入手动编辑标记，参考对齐默认不覆盖它们；需要覆盖时，在对齐审阅里对这些行逐行确认“仍要替换”。

最后更新：2026-11-16 12:30（Asia/Taipei）
