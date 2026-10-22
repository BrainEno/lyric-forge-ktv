# Handoff

## 目标

改进逐行试听和人工人声时间戳标记：歌词列表每一行在时间戳左侧显示播放/暂停按钮；行编辑器把时间边界明确称为“人声起点/人声终点”，可直接把当前播放位置标记为边界，并提供 ±10ms 微调。

## Git 现场

- 本执行环境仅提供 GitHub API，没有本地 checkout；不能提供真实的 git status --short、git diff --stat 或 git log --oneline -5 输出。
- 审查基线 main：0474fdff3dbd985b6c0db9aeabb2ccf0941a01d5。
- 工作分支：feat/lyric-row-audition-time-markers-20261022，目标 base 为 main。
- 先提交的 UI 测试：738361d6d3146d662694137e8b2a2937d1af8740；行级试听组件提交：f58d16efb7cce5d22c97ec768506a5555195d806；编辑器与时间标记接线提交：a5eacfe797d2a42b8ec193c0c4c5f371bd5d384f；旧组件移除提交：90ce69570daab82607143285452a3b9e7b97bae7。
- Draft PR #138 已创建：https://github.com/BrainEno/lyric-forge-ktv/pull/138；当前无本地 Flutter 验证，GitHub 未返回相关 status checks / workflow runs。

## 已改文件

- lib/features/lyrics/presentation/widgets/lyric_row_audition_button.dart：音频可用时显示播放/暂停按钮，不再限制为智能复核模式。
- lib/features/lyrics/presentation/widgets/smart_review_audition_button.dart：删除旧的仅智能复核按钮实现。
- lib/features/lyrics/presentation/screens/lyric_editor_screen.dart：将单行试听按钮移动到时间戳左侧；时间编辑器改用人声起点/终点语义，增加标记当前播放位置与 ±10ms 微调。
- test/features/lyrics/presentation/widgets/smart_review_audition_button_test.dart：覆盖可试听行按钮、按钮与行点击隔离、播放/暂停状态、无音频时隐藏。
- docs/handoff.md、docs/work_log_index.md：更新本阶段交接信息。

## 检查结果

- 静态检查确认编辑器内不再引用旧 SmartReviewAuditionButton/isSmartReview API，时间编辑器的两个起止入口都提供人声标记标签。
- 未运行 dart format、flutter test、flutter analyze 或质量门：当前没有本地 checkout 或 Dart/Flutter 工具链。
- 未写不可变 work-log 条目，也未手工修改生成文件 docs/work_log.md；需本地验证通过后再记录完成任务。

## 下一步（唯一）

本地检出该分支，运行 dart format lib/features/lyrics/presentation/screens/lyric_editor_screen.dart lib/features/lyrics/presentation/widgets/lyric_row_audition_button.dart test/features/lyrics/presentation/widgets/smart_review_audition_button_test.dart；运行该定向 widget 测试、flutter analyze --no-pub、flutter test test/features/lyrics，以及 dart tool/work_log.dart write/check。完成后再把 PR 标记为 Ready。

## 已知风险

- 当前复用既有 LyricAuditionWindowService 来裁剪到当前行的试听范围；这次没有新增音频模型调用，也没有改变播放器会话。
- 模型自动判断单句人声真实起止时间仍未实现。现有 T0 审计未发现应用侧可向 Qwen ForcedAligner 传入任意歌词文本的公开调用路径，因此不能假装已有可直接使用的强制对齐端点。该能力需要单独研究本地对齐 adapter 和证据来源；本 PR 提供更顺手的人工标记兜底。
