# [2026-10-21 17:04] 智能复核逐项完成与确认记录

- Scope: 将智能复核从单纯风险排序推进为一轮可完成的人工校对流程。用户可以明确确认某行的歌词文本和时间轴目前可接受，系统会跳到剩余最高优先级行。确认以稳定行 ID 关联当前文本及起止时间，任一内容/时间变化后该确认自动失效，防止过期确认屏蔽新问题。
- Files: 新增 lib/features/lyrics/domain/services/lyric_review_decision_service.dart（复核记录、指纹与清理逻辑）；修改 lib/features/lyrics/domain/services/lyric_review_priority_service.dart（智能队列排除当前指纹一致的已确认行）；修改 lib/features/lyrics/presentation/screens/lyric_editor_screen.dart（确认/撤销标记、自动继续、确认状态徽标/空状态、智能队列滚动）；新增 test/features/lyrics/domain/services/lyric_review_decision_service_test.dart；扩展 test/features/lyrics/domain/services/lyric_review_priority_service_test.dart；更新 docs/lyric_review_alignment_plan.md、docs/work_log_index.md 与 docs/handoff.md。
- Validation: 仅完成 GitHub API 静态检查。当前执行环境无 Dart/Flutter 可执行文件，因此 dart format、两个定向测试、flutter analyze --no-pub、flutter test test/features/lyrics、全量 flutter test、scripts/quality_gate.ps1 和 work-log 生成/校验均未运行；不可据此声称代码已编译或测试通过。
- Notes: 复核标记存入 metadata['lyricReviewDecisions']，只有工程显式保存后才跨会话保留。指纹包括歌词文本和起止时间；编辑后旧标记不再生效。智能复核模式关闭播放跟随滚动，列表仅在筛选结果实际变化时回到顶部，避免播放状态每帧刷新打断审阅。PR 应保持 Draft 直到本地验证与多视口 UI 检查完成。
- Commit: 7de1c6bb42a459b0adba5e70cf12691d1ed07534
