# Handoff

> 单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 `AGENTS.md` 与 `docs/work_log_index.md`。
> 只写"下一位执行者"真正需要的东西，不要粘贴日志正文或大段 diff。

## 目标

参考歌词确认链路 A/B/C1/C2/C3/C3.1 已全部实现。本次会话完成 C3.1 对齐备份恢复 UI：新增纯 Dart `ReferenceAlignmentRestoreService`（probe 校验 + restore 生成，四类可区分失败）、恢复确认对话框与 `confirmReferenceAlignmentRestore` 完整交互（失败走 SnackBar、不改状态）、编辑器入口（备份存在且可解析才显示，恢复后清空会话级手动编辑索引、重置过滤器、夹取选中行、`_hasChanges = true` 不自动保存）。单槽语义：恢复成功即消耗备份键。工作树未提交，建议提交信息 `Add reference alignment backup restore flow`。C3 多视口人工复核与恢复流程真实工程全链路人工验证仍未做。

## Git 现场

```text
$ git status --short
 M docs/decisions.md
 M docs/lyric_review_alignment_plan.md
 M docs/work_log.md
 M docs/work_log_archive.md
 M docs/work_log_index.md
 M lib/features/lyrics/presentation/screens/lyric_editor_screen.dart
?? docs/log/entries/2026-10-20-1228-reference-alignment-backup-restore.md
?? lib/features/lyrics/domain/services/reference_alignment_restore_service.dart
?? lib/features/lyrics/presentation/widgets/reference_alignment_backup_dialog.dart
?? test/features/lyrics/domain/services/reference_alignment_restore_service_test.dart
?? test/features/lyrics/presentation/widgets/reference_alignment_backup_restore_test.dart

$ git diff --stat
 docs/lyric_review_alignment_plan.md  |  8 +++
 docs/work_log_archive.md             |  1 +
 lib/.../lyric_editor_screen.dart     | 69 +++++++++++++++++++++-
 （其余为文档/日志小改，共 89 insertions / 6 deletions）

$ git log --oneline -5
8be798e Update handoff after per-line review
e433303 Add per-line reference lyric review
9701155 Add reference lyric correction entry and apply flow
241f6a8 Add reference lyric alignment service
b186d81 Add lyric editor progress bar and insert-at-playback
```

## 已改文件

- 新增 `lib/features/lyrics/domain/services/reference_alignment_restore_service.dart`：`probeBackup`（missing / invalidShape / corruptDocument / lineCountMismatch）、`restore`（写 `referenceAlignmentRestore`、删备份键、保留旧 `referenceAlignment`，不修改入参）。
- 新增 `lib/features/lyrics/presentation/widgets/reference_alignment_backup_dialog.dart`：确认对话框（备份时间/来源/格式/行数 + 覆盖警告 + "恢复并覆盖"≥48dp）与 `confirmReferenceAlignmentRestore` 交互封装。
- 修改 `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`（67+/2−）：备份键改用共享常量、探测入口显隐、`_restoreAlignmentBackup`、AppBar/工具栏各一个入口。
- 测试：`reference_alignment_restore_service_test.dart`（9 例）、`reference_alignment_backup_restore_test.dart`（5 个 widget，390×844）。
- 文档：`docs/lyric_review_alignment_plan.md`（C3.1 小节）、`docs/decisions.md`（D-007）、本条目对应日志 `docs/log/entries/2026-10-20-1228-reference-alignment-backup-restore.md`、生成的 `docs/work_log.md`、`docs/work_log_index.md`、`docs/work_log_archive.md`（补归档轮出条目）、`docs/handoff.md`。

## 检查结果

- `dart format` 4 个新增文件 + widget 测试 → 0 changed；`lyric_editor_screen.dart` 未整文件格式化（HEAD 在当前 dart format 下本就不干净，整文件格式会产生约 300 行无关 diff，已回滚并只保留任务改动）。
- `flutter analyze lib/features/lyrics test/features/lyrics` → 无 error/warning，仅既有 4 条 info（3× `use_null_aware_elements`、1× `unnecessary_import`）。
- `flutter test test/features/lyrics/` → 80/80 通过（原 66 + 9 服务 + 5 widget）。
- `dart tool/work_log.dart check` → 0 error；2 条 warning：阶段 A 历史 commit-subject 告警（保留，勿用改日志方式消除）+ 本条目 commit-subject 告警（提交后自动消失）。
- 未运行全量 `flutter analyze` / 全量测试套件；多视口人工复核未做。

## 下一步

1. 提交本切片（信息：`Add reference alignment backup restore flow`），然后人工复核 C3 + 恢复 UI：390×844、844×390、768×1024、1024×768、1366×768、1600×900、1920×1080、2560×1440，含连续缩放；恢复流程人工链路：应用参考歌词 → 改几行 → 恢复（取消一次、确认一次）→ 保存 → 重开工程确认歌词、时间、globalOffset、metadata 正确。
2. 可选清理：被参考纠正的行上旧 `fallbackCandidates` 徽标仍在，应用时可按行索引清除。
3. 阶段 D（可选）：在线歌词搜索 provider + 对话框页签。

## 已知风险

- 恢复流程在编辑器内的全链路只在 harness/widget 层验证过；真实工程"恢复 → 保存 → 重开"需人工确认。
- 手动编辑基线仍是编辑器会话级；备份单槽，二次对齐会覆盖快照（旧快照只能在其被消耗前恢复一次）。
- `lyric_editor_screen.dart` 在当前 dart format 版本下整体不干净是既有状态；只做增量改动，勿整文件格式化。
- C1 断句/合并差异表现为"漏行 + 多余识别"，不做跨行重组。
- widget 测试只覆盖 390×844。
- 阶段 A 的日志 commit-subject 告警是历史差异，预期存在，不要用改日志的方式消除。

---

最后更新：2026-10-20 12:28
