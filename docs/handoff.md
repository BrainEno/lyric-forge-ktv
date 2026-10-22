# Handoff

## 目标

为双引擎备选歌词添加字符级差异视图，帮助用户直接看出主引擎与备选引擎的错词，并保留显式采纳，不自动覆盖。

## Git 现场

- 本执行环境只有 GitHub API，没有本地 checkout；不能提供未经运行的 git status --short、git diff --stat 或 git log --oneline -5。
- 核心候选发现修复 Draft PR #136：https://github.com/BrainEno/lyric-forge-ktv/pull/136
- 本阶段 Draft PR #137：https://github.com/BrainEno/lyric-forge-ktv/pull/137
- UI 工作分支：feat/show-asr-lyric-diffs-20261022；base 指向核心分支 fix/surface-weak-lyric-matches-core-20261022。
- 当前 UI 分支已包含核心分支 head 92f678fbbe4d1de7981ab13f2ce5d6ed602d397d。
- 当前环境没有运行 Flutter 验证，GitHub 未返回相关 status checks / workflow runs。

## 已改文件

- lib/features/lyrics/presentation/widgets/alternative_candidate_diff.dart：复用 CharacterDiffService 并排渲染主引擎/备选文本，删除片段显示红色删除线，备选新增/替换内容用强调色高亮。
- lib/features/lyrics/presentation/screens/lyric_editor_screen.dart：接入字符 diff；优先从 fallbackCandidates 读取原主引擎文本，即使输出文本已自动采用备选，也仍能看到原始差异；不再把缺失的备选误回退成另一份主文本。
- test/features/lyrics/presentation/widgets/alternative_candidate_diff_test.dart：覆盖 Ashin lady / passion lady 文本、删除线及强调样式。
- test/high_quality_transcription_service_test.dart：补测低置信主引擎输出自动采用备选时仍保存原始 primaryText/alternativeText。
- docs/handoff.md、docs/work_log_index.md：更新当前交接与后续方向。

## 检查结果

- 相对核心 PR #136 的代码/测试变更约 225 行；本次 handoff 与索引更新用于交接。
- 未运行 dart format、flutter test、flutter analyze 或质量门：当前没有本地 checkout 或 Dart/Flutter 工具链。
- 不创建不可变 work-log 条目，也不手动编辑生成文件 docs/work_log.md，直到真实本地验证通过。

## 下一步（唯一）

本地检出 UI 分支并运行 dart format lib/features/lyrics/presentation/screens/lyric_editor_screen.dart lib/features/lyrics/presentation/widgets/alternative_candidate_diff.dart test/features/lyrics/presentation/widgets/alternative_candidate_diff_test.dart test/high_quality_transcription_service_test.dart；再运行两个定向测试、flutter analyze --no-pub、flutter test test/features/lyrics、dart tool/work_log.dart write/check。PR #136 合并后，将本 PR base 改为 main。

## 已知风险

- 字符 diff 展示的是两个引擎的文本差异，不证明哪个引擎正确；仍需用户明确点击“采用备选”。
- 字符差异依赖原候选中的 primaryText/alternativeText；对旧工程已丢失这些字段的候选，只能以当前行文本作为退路。
- 行内播放与单句人声起止自动校准/简易手动打点仍是下一阶段；这次不触碰播放会话或歌词时间戳，避免影响现有 audition/offset 逻辑。
