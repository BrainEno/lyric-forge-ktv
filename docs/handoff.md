# Handoff

> 单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 `AGENTS.md` 与 `docs/work_log_index.md`。
> 只写"下一位执行者"真正需要的东西，不要粘贴日志正文或大段 diff。

## 目标

参考歌词确认链路阶段 A/B/C1/C2/C3 已完成并提交，最新提交为 `e433303`（逐行确认）。C3 新增字符级 diff、逐行采纳/跳过、全选高置信、手动编辑行二次确认、漏行待处理清单、时间轴整体开关；C2 的批量摘要对话框已移除，应用仍走显式保存并保留备份/溯源 metadata。工作树干净，剩余工作是人工复核 C3、对齐备份恢复 UI、清理纠正行的旧 `fallbackCandidates` 徽标，最后才是阶段 D 在线歌词搜索。

## Git 现场

```text
$ git status --short
(clean)

$ git diff --stat
(empty)

$ git log --oneline -5
e433303 Add per-line reference lyric review
9701155 Add reference lyric correction entry and apply flow
241f6a8 Add reference lyric alignment service
b186d81 Add lyric editor progress bar and insert-at-playback
b575f1a Make playback progress bars seekable with hover time hints
```

## 已改文件

- 新增 `lib/features/lyrics/domain/services/character_diff_service.dart`：按 Unicode 码点的 LCS diff，合并相邻片段，超长行退化。
- 新增 `lib/features/lyrics/presentation/widgets/reference_alignment_review.dart`：逐行确认面板（diff 卡片、采纳/跳过、高置信全选、手动编辑锁、漏行待办、时间轴开关）。
- 修改 `lib/features/lyrics/domain/services/reference_alignment_applier.dart`：`acceptedReferenceIndices` 显式选择、`skippedBySelectionIndices`、时间轴与文字选择独立。
- 修改 `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`：接入逐行确认、有效保护集合、溯源字段。
- 删除 `lib/features/lyrics/presentation/widgets/reference_alignment_summary_dialog.dart`。
- 测试：`character_diff_service_test.dart`（10）、`reference_alignment_applier_test.dart`（+6）、`reference_alignment_review_test.dart`（2 个 widget）。
- 文档：`docs/lyric_review_alignment_plan.md`、`docs/decisions.md`（D-006）、本条目、`docs/work_log.md`、`docs/work_log_index.md`、`docs/work_log_archive.md`。

## 检查结果

- `dart format` 新增/改动文件 => 0 changed。
- `flutter analyze lib/features/lyrics test/features/lyrics` => 0 error / 0 warning；仅 4 条既有 info（3× `use_null_aware_elements`、1× `unnecessary_import`）。
- `flutter test test/features/lyrics/` => 66/66 通过。
- `dart tool/work_log.dart check` => 0 error；仅剩阶段 A 既有的 1 条 commit-subject 告警。
- 未运行全量 `flutter analyze` / 全量测试套件。

## 下一步

1. 人工复核 C3：390×844、844×390、768×1024、1024×768、1366×768、1600×900、1920×1080、2560×1440，含连续缩放；重点看逐行卡片、长行 diff、底栏按钮、手动编辑解锁、漏行清单和时间轴开关。
2. 实现对齐备份恢复 UI：当前 `metadata['referenceAlignmentBackup']` 是单槽快照，尚无入口；恢复前要确认覆盖当前文档，并保留溯源。
3. 可选清理：被参考纠正的行上旧 `fallbackCandidates` 徽标仍在，应用时可按行索引清除。

## 已知风险

- 手动编辑基线是编辑器会话级，重开工程后无法判断"已改过"，只能靠单槽备份兜底。
- 备份为单槽，二次对齐会覆盖上次快照；目前没有恢复入口。
- C1 断句/合并差异表现为"漏行 + 多余识别"，不做跨行重组。
- 时间轴整体替换后 `globalOffset` 归零；仅在参考与草稿 1:1、全部带时间戳、本次无手动编辑时开放。
- widget 测试只覆盖 390×844，真实工程保存重开与其余视口需人工确认。
- 阶段 A 的日志 commit-subject 告警是历史差异，预期存在，不要用改日志的方式消除。

---

最后更新：2026-10-20 12:04
