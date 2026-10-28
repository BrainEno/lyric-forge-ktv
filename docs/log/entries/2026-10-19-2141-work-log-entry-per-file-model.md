# [2026-10-19 21:41] 工作日志改为条目单文件化并补回丢失记录

- Scope: 把工作日志从"单文件追加 + 手工轮转"改为"一条任务一个不可变条目文件 + 脚本生成的活动摘要"，并把被 PR #124 合并覆盖而丢失的三条记录（20:33 / 20:58 / 21:22）从 git 历史逐字取回；同时新增 `docs/decisions.md`（稳定决策）与 `docs/handoff.md`（中断交接）两个固定载体。新会话的启动上下文因此稳定在 AGENTS.md + 索引 + 1–3 个条目文件，条目正文不再参与分支合并冲突。
- Files: `AGENTS.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/decisions.md`, `docs/handoff.md`, `docs/log/entries/*.md`（26 条历史 + 本条）, `scripts/build_work_log.ps1`
- Validation:
  - 条目拆分保真脚本（逐条比对旧 `work_log.md` / `work_log_archive.md` / `git show 14679b6:docs/work_log.md` 的正文）=> 26/26 条正文逐字一致
  - `powershell -File scripts/build_work_log.ps1 -Write` => 生成活动摘要（8 条活动 / 19 条归档）
  - `powershell -File scripts/build_work_log.ps1 -Check` => success（摘要未过期、归档条目均被引用）
  - 日志完整性检查（链接可解析、条目文件全部被引用、五个必需字段齐全、决策四字段齐全）=> success
  - `git diff --check` => success（仅 Windows LF→CRLF 提示）
  - 本次未改动任何 Dart 代码，未运行 `flutter analyze` / `flutter test`
- Notes: 旧日志采用"轮转即删行"的破坏性编辑，是 `536a13d` 合并时整体覆盖 `docs/work_log.md`、抹掉三条已提交记录的直接原因；改为条目文件后正文永不移动，轮转只影响几行摘要。归档导航 `docs/work_log_archive.md` 仍是手工维护（每退出一条活动窗口需补一行），完整 lint（`scripts/check_work_log.ps1`）与 `quality_gate` 集成留到下一切片。Windows PowerShell 5.1 会以 ANSI 读取无 BOM 的 `.ps1`，因此 `scripts/build_work_log.ps1` 保持纯 ASCII，需要中文文案的脚本必须带 UTF-8 BOM。
- Commit: `Move work log entries to per-task files`
