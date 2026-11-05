# Handoff

## 目标

本切片将 ForcedAligner 不支持项目语言时的用户提示移出 domain。解析器只抛出携带原始语言值的 typed exception；presentation 负责生成原有中文指导文案，编辑器仍保留原错误前缀和完整提示。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/935b04e1-lyric-forge-ktv`。
- 基线：PR #349 已合并，merge commit `c79538af183b47b805a2e692dccd7974b9cef817`。
- 实现提交：`55ceb4d refactor: move ForcedAligner language guidance to presentation`。
- PR #350：<https://github.com/BrainEno/lyric-forge-ktv/pull/350>，OPEN，等待 review；没有本 PR 的合并授权。
- Pinned Flutter Quality Gate run `42004606274` 在实现/测试 head `55ceb4dddb82c3a48ce2d560ba85f67ca488fbd9` 通过。文档更新后的 run `42005165752` 曾因无关 Media Hub upload deadline 测试失败；后续文档 head `022afc1e6563bcfbdeea0fa4ef6039af7bd562e0` 的 run `42005686105` 已通过。若 PR head 再变化，须重新检查最新 gate。
- PR #348、#349 已分别按其各自授权/流程处理；这些状态不构成对 PR #350 的合并授权。Issue #335 保持 CLOSED。

## 已改文件

- `lib/features/lyrics/domain/proofreading/forced_alignment_language.dart`：未知语言抛出 `ForcedAlignmentLanguageResolutionException` 并保留原始语言，不再组装自由提示文案。
- `lib/features/lyrics/presentation/lyric_review_strings.dart`：映射原有 ForcedAligner 语言指导文案。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`：识别 typed exception 后由 presentation 格式化提示；其他异常维持既有处理。
- resolver tests 验证异常数据，presentation string test 验证原文。
- `docs/log/entries/2026-11-05-1745-move-forced-aligner-language-guidance-to-presentation.md` 与 work-log 导航记录本切片。

## 检查结果

- `git diff --check` 通过。
- 临时 WASM `@wasm-fmt/dart_fmt` 对 changed Dart files 的格式检查通过。
- 本地没有 Flutter/Dart SDK，未运行本地 analyzer 或 tests。
- Pinned Flutter Quality Gate run `42004606274` 在实现/测试 head 通过。文档更新后 run `42005165752` 曾在无关 Media Hub upload deadline 测试失败；随后 PR-head run `42005686105` 全量通过。任何后续 PR-head 更新仍需复核最终 gate。

## 下一步

PR #350 保持 OPEN，等待 review 和最新 PR-head gate；未经用户明确授权不得合并。后续继续一次只迁移一个可独立验证的用户可见歌词校对文案切片。

## 已知风险

- 只将未知 ForcedAligner 语言的提示改为 typed data；其他校对流程中的异常提示不在本切片范围。
- 本地没有 Flutter/Dart SDK，验证依赖固定工具链 CI。
- native、KTV recovery、runtime-release、icon 和其他 specialist workflows 未逐项审计。

最后更新：2026-11-05（Asia/Hong_Kong）
