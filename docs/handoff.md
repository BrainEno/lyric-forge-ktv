# Handoff

## 目标

把时间轴校对和成品交付也做成批量工具。

- 「校对」菜单新增“检查时间轴”：按规则修复重叠、缺失结束时间、负开始时间、超出音频和顺序颠倒；识别摘要卡新增“时间轴问题 N 行”提示。
- 「校对」菜单新增“平移 / 伸缩时间轴”：整段平移，或用两点校准修正速度偏差。
- 导出支持 LRC（可选间奏清屏）、SRT、WebVTT、纯文本，带预览。导入端同步补齐：LRC 结束标记、WebVTT 转义。

所有改动都是可撤销的编辑，不自动保存。合并前先征求用户确认。

## Git 现场

- 分支：`arena/7e88cd21-lyric-forge-ktv`，基于 main `5a965d31341be7601f7b8374586830b79c37a289`。
- 验证用的临时 workflow 和它提交的结果文件已在开 PR 前删除，不进入 PR diff。

## 已改文件

- **领域服务（`lib/features/lyrics/domain/services/`）**
  - `lyric_timeline_repair_planner.dart`（新）：时间轴修复计划。
    - 每行汇总一条修复，并说明原因。
    - 判断错位行，挪到相邻行之间。
    - 应用选中的修复，并写入 `autoRepaired` 来源。
    - 返回剩余冲突。
  - `lyric_timing_shift_service.dart`（新）：
    - 平移和两点线性映射，带边界夹取与冲突对比。
    - 时间输入的解析和格式化（`parseLyricTimeInput` / `formatLyricTimeInput`）。
  - `lyric_export_encoder.dart`（新）：LRC/SRT/WebVTT/纯文本编码，以及统一的 cue 规则。
  - `lyric_file_export_service.dart`：新增 `exportFile`。
  - `lyric_draft_health_service.dart`：新增 `timelineRows`。
- **数据层**
  - `local_lyric_file_export_service.dart`：委托给编码器，新增 `exportFile` 和 `normalizedFileName`。
  - `local_lyric_file_import_service.dart`：LRC 空时间标签视为上一行结束；WebVTT 反转义。
- **界面**
  - `widgets/lyric_timeline_repair_dialog.dart`（新）、`widgets/lyric_timing_shift_dialog.dart`（新）、`widgets/lyric_export_dialog.dart`（新）。
  - `controllers/lyric_export_coordinator.dart`（新）：导出流程，记住上次选择的格式。
  - `controllers/lyric_batch_text_tools_coordinator.dart`：接入两个新工具；本工程音频暂停时，把播放头作为目标时间传入。
  - `lyric_batch_text_edit.dart`（`timelineRepair`、`timingShift`）、`lyric_proofread_menu_button.dart`、`lyric_editor_toolbar.dart`（菜单项改为“导出歌词”）、`lyric_editor_content.dart`、`lyric_recognition_summary_card.dart`。
  - `screens/lyric_editor_screen.dart`：导出逻辑移出，文件从 1198 行降到 1178 行。
- **文档**：`decisions.md`（D-019）、本文件、工作日志条目 `2026-11-16-1800`。

## 检查结果

全部来自 GitHub Actions 临时 workflow（运行 43809755770），沙箱里没有 Dart/Flutter 工具链。

- `dart format`：改动文件已格式化。
- `flutter analyze`：没有 error 或 warning，186 条 info，与 main 相同。
- `flutter test` 全量：2477 通过，2 跳过，0 失败（main 为 2428 通过）。
- `dart tool/work_log.dart write` 和 `check`：通过。
- `lyric_editor_screen.dart`：1178 行。

## 下一步

- 用 #413 的真实歌曲基线校准估算参数：每个演唱单位 0.35 秒、1–6 秒、0.2 秒下限、1.5 秒清屏、4 秒分段。
- 可以考虑导出 ASS 卡拉 OK 字幕（`\k` 逐字时间），可以先按字数比例估算。
- 可以考虑“打轴模式”：播放中按键依次标记每行起点。现有“标记人声起点”已经能逐行使用。

## 已知风险

- 错位行判定是推测，默认不勾选，需要试听确认。
- 摘要卡拿不到音频时长，时间轴提示不统计“超出音频”；打开工具时会完整检查。
- 两点校准假设速度偏差在所选范围内是线性的。偏差不均匀时，可以分段多次校准。

最后更新：2026-11-16 18:00（Asia/Taipei）
