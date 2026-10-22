# Handoff

## 目标

T1b：实现纯 Dart 参考歌词清洗器。tokenizer/常量在前置 T1a PR 中；本阶段先提交 sanitizer 测试，再加入实现。Flutter/Dart 验证尚待本地执行。

## Git 快照

- 远程基线：`main @ c808d5244e8371afe62cefa6176cf38f81bf2380`。
- 分支：`feat/lyric-proofreading-t1-reference-sanitizer-20261022`；最近提交为 sanitizer 契约测试。
- 当前环境没有本地 checkout；无法取得真实的 `git status --short`、`git diff --stat` 与 `git log --oneline -5` 输出，不在此伪造。

## 已改文件

- `lib/features/lyrics/domain/proofreading/reference_text_sanitizer.dart`
- `test/features/lyrics/domain/proofreading/reference_text_sanitizer_test.dart`
- `docs/handoff.md`

前置 T1a PR #131 包含 `ProofreadConstants`、`LyricTokenizer` 与 tokenizer 测试。本 PR 单独完成 sanitizer，便于控制单任务改动行数。未改 CI、pubspec、UI 或生成式 `docs/work_log.md`；验证未执行前不新增完成态日志条目。

## 检查结果

- 已覆盖段落标记、前 3 个非空行的标题清理、署名、页面噪声、和声保留与重复歌词不去重。
- 未运行 `dart format`、`flutter analyze --no-pub` 或定向测试：环境中没有 Dart/Flutter 可执行文件或本地 checkout。
- 本阶段 sanitizer 测试先于实现提交，尚不能据此声称测试通过。

## 下一步（唯一）

先对前置 T1a PR #131 做本地格式化、analyze 和 tokenizer 测试；合并后再对包含 tokenizer + sanitizer 的组合运行两个定向测试与 `flutter test test/features/lyrics`。

## 已知风险

- 当前环境未运行任何 Dart/Flutter 检查，PR 应保持 Draft。
- Qwen 任意文本强制对齐与 Whisper 上文条件仍属于 T0 留下的待验证项，不是本 PR 的范围。
