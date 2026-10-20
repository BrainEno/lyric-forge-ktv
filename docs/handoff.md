# Handoff

> 单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 `AGENTS.md` 与 `docs/work_log_index.md`。

## 目标

歌词校正链路阶段 A/B/C1/C2/C3/C3.1 已完成并提交：进度条、编辑器定点插入、参考歌词对齐、逐行确认、对齐备份恢复都已落地。本轮复核确认 C3.1 已在 `de91642` 实现，歌词模块 80/80 测试通过、scoped analyzer 无问题；本轮只修正了被写成英文小节的交接文件，没有重复实现备份恢复。下一步是人工复核多视口与完整恢复流程，然后清理纠正行上残留的 `fallbackCandidates` 徽标。

## Git 现场

```text
$ git status --short
(clean)

$ git diff --stat
(empty)

$ git log --oneline -5
7bf6efd Fix all analyzer lint infos
de91642 Add reference alignment backup restore flow
8be798e Update handoff after per-line review
e433303 Add per-line reference lyric review
9701155 Add reference lyric correction entry and apply flow
```

## 已改文件

- 仅修改 `docs/handoff.md`：恢复工作日志 lint 要求的固定小节，并把下一步从“提交 lint 清理”更新为真实剩余工作。
- 本轮未改业务代码；备份恢复实现仍为 `de91642`。

## 检查结果

- `flutter test test/features/lyrics/` => 80/80 通过。
- `flutter analyze lib/features/lyrics test/features/lyrics` => No issues found。
- `dart tool/work_log.dart check` => 修正后运行确认（预期仅剩阶段 A 历史 commit-subject 告警）。
- 未运行全量 `flutter analyze` / 全量测试套件。
- 未做真实桌面/移动端人工复核。

## 下一步

1. 人工复核 C3/C3.1：390×844、844×390、768×1024、1024×768、1366×768、1600×900、1920×1080、2560×1440，含连续缩放；重点看逐行卡片、长行 diff、底栏按钮、手动编辑解锁、漏行清单、恢复入口与确认对话框。
2. 端到端流程：应用参考歌词 → 改几行 → 恢复并覆盖 → 取消一次/确认一次 → 保存 → 重开工程，确认歌词、时间、`globalOffset`、`metadata['referenceAlignmentRestore']` 正确，且备份键已被消耗。
3. 可选清理：被参考纠正的行上旧 `fallbackCandidates` 徽标仍在，应用时可按行索引清除。

## 已知风险

- C3/C3.1 的 widget 测试只覆盖 390×844，其他视口和真实工程保存重开仍需人工确认。
- 备份为单槽，恢复成功即消耗；二次对齐会覆盖上一份快照，没有多级撤销。
- 恢复后清空会话级 `_manuallyEditedLineIndices`，这是有意的索引安全处理；重开工程后仍无持久化的手动编辑基线。
- 时间轴整体替换后 `globalOffset` 归零；仅在参考与草稿 1:1、全部带时间戳、本次无手动编辑时开放。
- 阶段 A 的日志 commit-subject 告警是历史差异，预期存在，不要用改日志的方式消除。

---

最后更新：2026-10-20 13:40
