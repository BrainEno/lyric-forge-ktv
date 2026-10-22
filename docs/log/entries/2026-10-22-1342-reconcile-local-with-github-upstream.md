# [2026-10-22 13:42] 对齐本地分支与 GitHub 上游并修复 sanitizer 编译错误

- Scope: 对照 GitHub `BrainEno/ScribeForge` 与 `BrainEno/lyric-forge-ktv` 两个远程仓库与本地代码库，排查代码冲突并保留完成质量最高、朝最新功能推进的版本。ScribeForge 是独立的 Python OCR 项目，本地克隆无冲突、仅落后 5 个提交，已快进同步并通过全部测试。lyric-forge-ktv 本地 `main` 落后 `origin/main` 两个提交，且暂存区存在一份并行的 T1 早期实现——只有测试与常量、缺少 `lyric_tokenizer.dart` 与 `reference_text_sanitizer.dart` 两个实现文件，无法编译。现以已合并的上游实现为准：快进到 `origin/main`（PR #130 契约文档 + PR #131 分词器与常量），再并入尚未进入 main 的 PR #132（参考歌词清洗器），并修复上游 PR #132 遗留的编译错误与格式化问题。

- Files:
  - `lib/features/lyrics/domain/proofreading/reference_text_sanitizer.dart`（PR #132 新增；`RegExp` 无 const 构造器导致编译失败，改为 `static final`；`\s+` 正则提升为静态字段；补齐花括号 lint）
  - `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`（`dart format`）
  - `test/features/lyrics/domain/proofreading/lyric_tokenizer_test.dart`（`dart format`）
  - `test/features/lyrics/domain/proofreading/reference_text_sanitizer_test.dart`（PR #132 新增）
  - `docs/log/entries/2026-10-22-1258-document-lyric-proofreading-v2-contracts.md`（补回上游缺失的 T0 工作日志条目）
  - `docs/log/entries/2026-10-22-1342-reconcile-local-with-github-upstream.md`（本条目）
  - `docs/handoff.md`（重写为对齐后的真实状态）
  - `docs/work_log.md`、`docs/work_log_archive.md`（`dart tool/work_log.dart write` 重新生成）
  - `docs/work_log_index.md`（T1 状态更新）

- Validation:
  - `dart format lib/features/lyrics/domain/proofreading/ test/features/lyrics/domain/proofreading/` → `Formatted 5 files (0 changed)`。
  - `flutter analyze --no-pub` → `No issues found!`（退出码 0）。修复前为 6 issues（4 error + 2 info）。
  - `flutter test test/features/lyrics/domain/proofreading` → `All tests passed!`（6/6，退出码 0）。
  - `flutter test test/features/lyrics` → `All tests passed!`（221/221，退出码 0；此前基线 215）。
  - `dart tool/work_log.dart check` → `Work log lint passed (0 errors, 0 warning(s))`。
  - ScribeForge（`D:\develop\python-projs\ScribeForge`）：`.venv\Scripts\python.exe -m pytest -q --no-cov` → 355 项全部通过。

- Notes: 保留上游已合并版本而非本地 T1 早期版本，因为上游含完整实现且本地版本缺少两个实现文件、无法编译；本地被取代的内容完整保存在 `backup/local-t1-partial-20261022`（提交 `851f51e`），其中逐用例 `group` 写法的分词器/清洗器测试与上游扁平写法功能等价，若要采用需在 PR #132 合入之后进行以免与待合分支冲突。本地 `main` 现含 PR #132 的合并提交 `c3e9f87`，而 GitHub 上 `feat/lyric-proofreading-t1-tokenizer-20261022` 仍未并入 `main`，推送前需决定直接推 `main` 还是走 PR 流程，避免同一内容重复合入。本地 `main` 与 `origin/main` 的差异尚未推送。上游 PR #130/#131/#132 三者均未写工作日志条目，本地仅补回 T0 一条，T1 两条仍缺。

- Commit: Reconcile local branch with upstream and fix sanitizer compile errors
