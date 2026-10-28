# [2026-10-22 02:40] 行级试听边界控制与循环试听（阶段 I）

- Scope: 智能复核列表支持行内边界试听与循环控制。增加纯 Dart LyricAuditionWindowService 计算 1 秒前置起止窗口，复用既有播放会话自动在行末暂停或单行循环，编辑时间轴/全局偏移时自动清除试听窗口。清理本地遗留远程 Agent 目录并加入 .gitignore。
- Files: lib/features/lyrics/domain/services/lyric_audition_window_service.dart, lib/features/lyrics/presentation/lyric_review_strings.dart, lib/features/lyrics/presentation/widgets/smart_review_audition_button.dart, lib/features/lyrics/presentation/screens/lyric_editor_screen.dart, .gitignore, test/features/lyrics/domain/services/lyric_audition_window_service_test.dart, test/features/lyrics/presentation/widgets/smart_review_audition_button_test.dart, docs/handoff.md, docs/work_log_index.md, docs/work_log_archive.md, docs/work_log.md, docs/log/entries/2026-10-22-0240-bounded-lyric-line-audition.md
- Validation: dart format 相关 6 个文件通过；flutter analyze --no-pub 报告 0 告警 0 错误；flutter test 定向单测 9/9 与组件测试 4/4 通过；flutter test test/features/lyrics 215/215 通过；flutter test 全量 549/549 测试通过；dart tool/work_log.dart check 与 scripts/quality_gate.ps1 验证通过。
- Notes: 修复了 PR #129 在本地执行时发现的一处未定义变量编译错误（playbackBelongsToProject）与 3 处冗余非空判断警告。从代码库彻底清除了远程 Hermes Agent 脚手架与暂存内容并添加忽略规约。
- Commit: Add bounded lyric audition and loop control in smart review
