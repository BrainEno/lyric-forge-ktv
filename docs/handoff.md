# Handoff

> 单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 `AGENTS.md` 与 `docs/work_log_index.md`。

## 目标

歌词校正链路阶段 A/B/C1–C4 与可靠性硬化 E1–E4 已完成并提交。E1–E3 修时间轴校验、插入音频边界、LRC 冲突、对齐阈值状态、歧义匹配选择与回归样本；E4 把“手工编辑保护”从会话级行索引改为稳定 `lineId` 并持久化到工程，重开工程后再次对齐仍跳过用户改过的行，同时给 `metadata['referenceAlignment']` 加了显式索引基准与稳定行标识，并用文件仓库级测试覆盖“保存→重开→再次对齐”。下一步是人工多视口复核，之后可选做 Phase D 在线歌词搜索。

## Git 现场

```text
$ git status --short
(clean)

$ git diff --stat
(empty)

$ git log --oneline -5
04a4922 Regenerate work log after E4.3 provenance entry
5e7dde8 Record reference alignment provenance with stable line ids
fd9dfa9 Regenerate work log after E4.2 marker persistence entry
8cb7d30 Persist manual-edit markers by stable line identity
93d3054 Regenerate work log after E4.1 line identity entry
```

## 已改文件

- `lib/features/project/domain/models/lyric_document.dart`：`LyricLine.id`（可选，JSON 不写空键）。
- 新增 `lib/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart`：补齐行标识、持久化/恢复/清理手工编辑标记、派生受保护索引。
- 新增 `lib/features/lyrics/domain/services/reference_alignment_provenance_builder.dart`：`metadata['referenceAlignment']` 纯构建器（`indexBase: 'pre-application'`、`lineId`、`insertBeforeAsrLineIndex`/`appliedLineIndex`）。
- `lib/features/lyrics/domain/services/reference_alignment_applier.dart`：`appliedIndexByOriginalIndex` 映射、`appliedLineIndex` 别名。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`：基于 `lineId` 的保护、加载/保存/备份恢复/插入/删除/对齐后补标识、改用溯源构建器，删除 `_shiftEditedIndices`。
- 测试：`test/features/project/lyric_document_test.dart`(6)、`lyric_manual_edit_marker_service_test.dart`(11)、`reference_alignment_provenance_builder_test.dart`(3)、`test/features/lyrics/reference_alignment_persistence_test.dart`(1，仓库级保存重开 E2E)；扩展 `reference_alignment_applier_test.dart`(+2)。
- 文档：`docs/decisions.md`（D-009；D-007 标部分已取代）、`docs/work_log_index.md`、`docs/work_log.md`、`docs/work_log_archive.md`、本文件。

## 检查结果

- `flutter analyze --no-pub`（全项目）=> No issues found。
- `flutter test --no-pub` => 492 通过、2 跳过、0 失败。
- `flutter test --no-pub test/features/lyrics/` => 158/158 通过。
- `dart tool/work_log.dart check` => 0 errors, 0 warnings。
- 未启动真实桌面/移动 UI，多视口人工复核未执行。

## 下一步

1. 人工复核多视口：390×844、844×390、768×1024、1024×768、1366×768、1600×900、1920×1080、2560×1440（含连续缩放）打开编辑器 → 改词 → 保存 → 重开，确认改词保留、再次参考对齐时该行锁定跳过、状态不被缩放重置。
2. 真实工程端到端：应用参考对齐（含补行）→ 保存 → 重开，核对 `metadata['manuallyEditedLineIds']`、`metadata['referenceAlignment']` 的 `indexBase`/`lineId`/`appliedLineIndex`；再验证备份恢复后保护与溯源仍自洽。
3. Phase D 在线歌词搜索仍为可选项，当前未实现。

## 已知风险

- 编辑器页面依赖 `ServiceLocatorGlobal` 完整真实服务图（含音频插件），无法普通 widget 测试；页面装配层只有 analyzer 与代码审查覆盖。
- 旧工程/旧备份没有行标识时会补新标识，旧的手工编辑标记自然失配（不误保护，但也无法恢复保护）。
- `insertions[].asrLineIndex` 在 metadata 中改名为 `appliedLineIndex`；仓库内无读取方，外部脚本若依赖旧键需同步。
- 歧义检测只覆盖“锚点之间夹着未匹配 ASR 行”和“空隙不足”；跨行重组、断句差异仍表现为“需确认”漏行。
- 备份为单槽，恢复成功即消耗；二次对齐会覆盖上一份快照，没有多级撤销。
- `lyric_editor_screen.dart` 未整体格式化（HEAD 处于格式化器漂移状态），只格式化新增行，避免无关 diff。

---

最后更新：2026-10-21 11:56
