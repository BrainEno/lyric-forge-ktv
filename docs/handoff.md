# Handoff

单槽位交接文件：每个会话在中断或结束前覆盖写一次，新会话先读它，再读 AGENTS.md 与 docs/work_log_index.md。

## 目标

继续降低歌词识别后的人工校对负担。PR #125（对齐后逐行对比与保守时间轴自动修复）和 PR #126（可解释智能复核优先队列）已在远程 main 合并。当前工作分支为 feat/guided-smart-review-confirmation-20261021，最新代码提交 2cd74b77d2f7ad99e40ffcddbb82369554b250e4；正在开发“持久化复核决策 + 确认本行无误并继续”。

## 本分支内容

- 新增 LyricReviewDecisionService：基于稳定 lineId 保存确认记录，以歌词文本和起止时间的 FNV-1a 指纹判断记录是否仍有效；变更内容或时间会自动重新进入复核队列。
- LyricReviewPriorityService.rank 排除当前指纹一致的已确认行。
- 编辑器检查器增加“确认本行无误并继续 / 取消已复核标记”；确认后回到智能复核模式并选中剩余最高优先级行；队列滚动只在筛选实际变化时重置，智能复核时不由播放自动滚动打断。
- 增加复核决定 service 测试，并扩展优先级队列测试。

## Git 现场

branch: feat/guided-smart-review-confirmation-20261021
base: main @ 228c258f1c6c1b07c6c7503cba34fa41475c8ebd
commit: 7de1c6bb42a459b0adba5e70cf12691d1ed07534

## 验证状态

- 已完成 GitHub API 静态检查：检查修改的导入、构造器参数与调用点、智能队列筛选/空状态、决策元数据指纹和测试场景。
- 未运行 dart format、flutter analyze 或任何 Flutter 测试：当前容器无 dart / flutter 可执行文件，也没有可用的本地 checkout。
- 必须由本地 OpenCode 执行：先格式化变更文件；运行两个复核服务定向测试、flutter analyze --no-pub、flutter test test/features/lyrics、全量 flutter test、scripts/quality_gate.ps1 以及 dart tool/work_log.dart write/check。
- PR 应保持 Draft，直到以上验证通过并人工检查至少 390×844、1024×768、1366×768、1600×900。

## 变更文件

- lib/features/lyrics/domain/services/lyric_review_decision_service.dart
- lib/features/lyrics/domain/services/lyric_review_priority_service.dart
- lib/features/lyrics/presentation/screens/lyric_editor_screen.dart
- test/features/lyrics/domain/services/lyric_review_decision_service_test.dart
- test/features/lyrics/domain/services/lyric_review_priority_service_test.dart
- docs/lyric_review_alignment_plan.md
- docs/log/entries/2026-10-21-1704-guided-smart-review-confirmation.md
- docs/work_log_index.md

## 单一下一步

在本地 OpenCode checkout 同步此分支，先运行格式化/测试/analyze；若出现问题，先修到干净，再完成手动窗口验证与 work-log 生成，然后将 PR 从 Draft 改为 Ready for review。

## 已知边界

- 确认记录随用户显式保存持久化；单击确认不会自动保存工程。
- 决策指纹只用于内容变更检测，不是安全散列。行文本或起止时间任一改变都会要求重新复核；仅置信度或元数据变化不会失效。
- 不会自动更改歌词或时间轴，只记录用户确认并跳转；时间轴异常若未实际修改，用户确认本行后会在当前指纹下暂时退出队列。
- 本分支没有运行 Flutter 工具链，代码尚未获得本地编译/测试背书。

最后更新：2026-10-21 17:04
