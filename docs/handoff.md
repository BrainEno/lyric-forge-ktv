# Handoff

> 单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 `AGENTS.md` 与 `docs/work_log_index.md`。
> 只写"下一位执行者"真正需要的东西，不要粘贴日志正文或大段 diff。

## 目标

把工作日志流程从"单文件追加 + 手工轮转"迁移为"条目单文件化 + 脚本生成活动摘要"，并补回被合并覆盖丢失的历史记录（S1 已完成；后续为 S2 校验脚本、S3 分析器解锁）。

## Git 现场

```text
$ git status --short
(clean after this task's commit)

$ git log --oneline -3
<new>  Move work log entries to per-task files
14679b6 Sync lyrics flag into playback queue enrichment
603d645 Auto-link lyrics on first project save
```

## 已改文件

- `docs/log/entries/*.md` — 26 条历史条目（含从 `git show 14679b6:docs/work_log.md` 取回的 20:33 / 20:58 / 21:22 三条丢失记录）+ 本次 S1 条目；正文逐字保留。
- `docs/work_log.md` — 改为脚本生成的活动摘要（8 条）。
- `docs/work_log_archive.md` — 改为阶段分组导航（19 条），正文链接到条目文件。
- `docs/work_log_index.md` — 新增日志布局、decisions/handoff 指针，修正快照日期与待办线索。
- `docs/decisions.md`（新）— D-001 LRC offset 烘焙、D-002 record+flutter_soloud、D-003 代理策略、D-004 日志单文件化。
- `docs/handoff.md`（新）— 本文件，交接模板。
- `AGENTS.md` — 日志章节改为新模型（条目文件写入方式、生成/校验命令、交接写法、决策写法）。
- `scripts/build_work_log.ps1`（新）— `-Write` 生成摘要、`-Check` 校验摘要是否过期及归档条目是否被引用。

## 检查结果

- 条目拆分保真比对（26 条正文逐字）=> success
- `powershell -File scripts/build_work_log.ps1 -Write` / `-Check` => success（8 活动 / 19 归档）
- 日志完整性检查（链接、条目覆盖、五字段、决策四字段）=> success
- `git diff --check` => success
- 本次未改 Dart 代码，未跑 `flutter analyze` / `flutter test`

## 下一步

写 `scripts/check_work_log.ps1`（条目命名与时间戳唯一、五字段齐全、摘要链接有效且为最新 N 条、index 快照日期与日志最新条目一致、`Commit:` 主题能在 git 历史中找到、决策字段齐全），并以可选 step 形式接入 `scripts/quality_gate.ps1`；完成标准：故意制造违规样本时脚本返回非 0，仓库现状下 `-Check` 通过。

## 已知风险

- `scripts/quality_gate.ps1` 目前不被任何 CI workflow 调用，接入文档校验**不会**改变 CI 行为；如需真正的 CI 门禁要先取得授权。
- Windows PowerShell 5.1 以 ANSI 读取无 BOM 的 `.ps1`，脚本内出现中文必须写 UTF-8 BOM，否则字面量损坏。
- 归档导航 `docs/work_log_archive.md` 仍是手工补行：条目退出一条活动窗口时需手工在对应阶段补一行，`-Check` 只能检出缺失、不能自动补齐。
- 全项目 `flutter analyze` 仍被 `test/features/player/fullscreen_ktv_interaction_surface_test.dart` 的 `WidgetTester.doubleTap`（不存在的 API）阻断，另有 3 个 warning 未修。

---

最后更新：2026-10-19 21:41
