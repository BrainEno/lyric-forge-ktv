# Handoff

## 目标

对齐本地代码库与 GitHub `origin/main`：合并上游已合并的 PR #130/#131，以及尚未并入 main 的 PR #132（参考歌词清洗器），并补回上游缺失的 T0 工作日志条目。本地 T1 早期实现（缺实现文件）保留在 `backup/local-t1-partial-20261022` 分支。

## Git 快照

- 分支：`main`；基线 `origin/main @ 3f354d7`（PR #130 契约文档 + PR #131 分词器与常量）。
- 合并来源：`582da9b`（PR #132，合并自 `feat/lyric-proofreading-t1-tokenizer-20261022`）。
- `git status --short`：
  ```
  M docs/handoff.md
  A docs/log/entries/2026-10-22-1258-document-lyric-proofreading-v2-contracts.md
  A lib/features/lyrics/domain/proofreading/reference_text_sanitizer.dart
  A test/features/lyrics/domain/proofreading/reference_text_sanitizer_test.dart
  ```
- `git log --oneline -5`：
  ```
  3f354d7 Add lyric tokenizer and proofread constants (#131)
  c808d52 Document lyric proofreading v2 contracts (#130)
  165db5b Add bounded single-line audition and loop control (#129)
  f531d35 Merge pull request #128 from BrainEno/feat/smart-review-inline-audition-20261021
  121d892 Merge branch 'main' into feat/smart-review-inline-audition-20261021
  ```
- 备份分支：`backup/local-t1-partial-20261022`（提交 `851f51e`），保存本地被上游取代的 T1 早期版本与 `docs/lyric_proofreading_v2_plan.md` 早期草稿。

## 已改文件

- `lib/features/lyrics/domain/proofreading/reference_text_sanitizer.dart`（PR #132 新增实现）
- `test/features/lyrics/domain/proofreading/reference_text_sanitizer_test.dart`（PR #132 新增测试）
- `docs/log/entries/2026-10-22-1258-document-lyric-proofreading-v2-contracts.md`（补回上游缺失的 T0 工作日志条目）
- `docs/handoff.md`（本文件，重写为对齐后的真实状态）

未改 CI、pubspec、UI、CI 工作流或生成式 `docs/work_log.md`（后者由 `dart tool/work_log.dart write` 重新生成）。

## 检查结果

- `dart format --output=none --set-exit-if-changed`（改动 Dart 文件）：通过。
- `flutter analyze --no-pub`：No issues found!
- `flutter test test/features/lyrics`：215/215 通过（0 失败）。
- `flutter test test/features/lyrics/domain/proofreading`：2/2 通过（tokenizer 与 sanitizer 契约测试）。
- `dart tool/work_log.dart check`：Work log lint passed (0 errors, 0 warning(s))。

## 下一步（唯一）

推进 T2：token 锚点对齐与 `referenceCoverage` 计算，纯 Dart domain 实现，先写契约测试再写实现。

## 已知风险

- PR #132 的内容目前在本地 `main` 上以合并提交形式存在，GitHub 上 `feat/lyric-proofreading-t1-tokenizer-20261022` 仍未并入 `main`；后续推送前需决定是把 `main` 推上去，还是改走 PR 流程，避免同一份内容重复合入。
- 本地 `main` 与 `origin/main` 的差异尚未推送，推送前需确认 PR 策略。
- `backup/local-t1-partial-20261022` 中的分词器/清洗器测试采用逐用例 `group` 写法，与上游扁平写法功能等价；若要采用需在 PR #132 之后再改，避免与待合分支冲突。
- Whisper 是否已关闭上文条件（`-mc 0`）仍未在目标机器上用 `whisper-cli --help` 核实；Qwen ForcedAligner 仍无独立 `/v1/align` 端点，词级时间只保存在 `rawJsonPath` 指向的外部 JSON。

最后更新：2026-10-22 14:05
