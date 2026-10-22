# Handoff

## 目标
T5 phase 4：为已有 ASR 行生成参考歌词文本纠错建议；不直接应用建议、不插入漏行、不覆盖受保护行或时间戳。

## Git 快照
- 分支：`feat/lyric-proofreading-t5-reference-suggestions-20261022` → `main`；预计 Draft PR #145。
- 基线 main：`b736c61d1b714fda459d0370be915d082a6e1c17`。
- 测试先行提交：`730f2bd6d11c479dc95e67ca2226e7a3f77c3368`；实现提交：`166a03f099ed71ccef800b9fd10df578970a22bf`；后续收敛/修复提交已追加到该分支，PR head 应以 GitHub 现场为准。
- PR #143 已合入 main；PR #144 仍为 Draft。#142 的重复片段代码被合并到旧的 #141 功能分支，未进入 main，因此 #144 单独移植代码。
- 本环境仅有 GitHub API，没有本地 checkout、Dart 或 Flutter 工具链，无法读取本地 git status/diff/log。

## 已改文件
- `lib/features/lyrics/domain/proofreading/asr_reference_correction_suggester.dart`：用现有参考歌词清洗与行级对齐生成文本建议；保留原始参考行索引与对齐状态/原因码；只建议现有、未保护且文本有差异的匹配行。
- `test/features/lyrics/domain/proofreading/asr_reference_correction_suggester_test.dart`：覆盖高相似度错字、低置信度候选、受保护行、标题/分段头清理后的原始索引、参考漏行不自动插入、导入警告与不可变结果。
- `docs/lyric_proofreading_v2_plan.md`、`docs/work_log_index.md`、`docs/handoff.md`：更新阶段和集成状态。

## 检查结果
- 静态核对：建议器只返回 current/suggested text 与相似度/状态/原因，不写回文档。参考 LRC 时间戳不被读取为输出时间；每条文本变更建议都要求重新定时。
- 未运行 `dart format`、定向测试、`flutter analyze --no-pub`、`flutter test test/features/lyrics` 或 `dart tool/work_log.dart check`；无本地测试或 CI 结果。
- 未创建 immutable work-log entry，未手动编辑生成的 `docs/work_log.md`。

## 下一步（唯一）
本地运行：
```powershell
dart format lib/features/lyrics/domain/proofreading/asr_reference_correction_suggester.dart test/features/lyrics/domain/proofreading/asr_reference_correction_suggester_test.dart
flutter test test/features/lyrics/domain/proofreading/asr_reference_correction_suggester_test.dart
flutter analyze --no-pub
flutter test test/features/lyrics
dart tool/work_log.dart check
```
通过后再将 PR #145 标为 Ready；并验证/合并 PR #144 的重复片段移植，避免 T5 功能只存在于旧分支。

## 已知风险
本建议器复用现有行级 Needleman–Wunsch 对齐，不处理多行重新分割，也不创建词级时间。歧义/低相似度/结构错配和参考导入警告会显式标注；改变文本后仍缺少独立的安全重定时阶段，当前结果不可直接应用。
