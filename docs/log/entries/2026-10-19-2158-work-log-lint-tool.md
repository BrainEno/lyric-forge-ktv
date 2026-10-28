# [2026-10-19 21:58] 为工作日志流程增加跨平台校验工具

- Scope: 给条目单文件化的日志流程加上机器校验：新增 `tool/work_log.dart`（`write` 生成活动摘要、`check` 校验、纯 Dart 无第三方依赖），覆盖条目命名与时间戳唯一性、五个必需字段、摘要是否过期、条目是否被引用、文档相对链接是否可解析、索引快照日期是否等于最新活动条目、决策与交接的固定字段；并把该校验接入 Windows/macOS 两套质量门禁，使日志规范能被自动执行而不是靠自觉。
- Files: `tool/work_log.dart`（新建）, `test/work_log_tool_test.dart`（新建）, `scripts/quality_gate.ps1`, `scripts/quality_gate.sh`, `AGENTS.md`, `docs/work_log.md`, `docs/work_log_index.md`, `docs/decisions.md`, `docs/handoff.md`, `docs/log/entries/2026-10-19-2158-work-log-lint-tool.md`
- Validation:
  - `flutter test test/work_log_tool_test.dart` => All 11 tests passed（覆盖合法夹具通过、摘要过期、字段缺失、文件名非法、时间戳重复、条目未被引用、链接断裂、索引快照不符、决策缺字段、交接缺章节）
  - `dart tool/work_log.dart check` => success（0 errors）；保留 2 条 commit-subject 警告
  - `flutter analyze --no-fatal-infos tool/work_log.dart test/work_log_tool_test.dart` => No issues found
  - `git diff --check` => 仅 `scripts/quality_gate.ps1` 的新增行被报 trailing whitespace（该文件在仓库中本就是 CRLF 存储，CR 被判为行尾空白）；其余文件 clean
  - `bash -n scripts/quality_gate.sh`（LF 版本）=> 通过，确认 shell 脚本仍是 LF，不会破坏 Linux/macOS 门禁
  - 未运行全量 `flutter test`；未改动 `lib/` 下的产品代码
- Notes: 校验实现最初写成 PowerShell（`scripts/build_work_log.ps1` 等三个脚本），但 Windows PowerShell 5.1 以 ANSI 读取无 BOM 脚本，中文字面量会被破坏，且 macOS/Linux 门禁无法复用，因此改为 Dart 工具并删除那三个脚本（上一条 S1 日志中提到的脚本名已随本次调整失效）。校验目前只在本地质量门禁中执行，尚未接入 GitHub workflow；`commit-subject` 规则只对活动窗口内的条目告警，历史条目冻结不检查——现有两条告警来自 2026-10-19 15:44 / 15:55 两条记录，其登记的提交主题在当前 git 历史中并不存在（当时以 PR 形式合入），属如实反映而非脚本误报。
- Commit: `Add work log lint tool and quality gate hook`
