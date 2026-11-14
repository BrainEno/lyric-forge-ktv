# Handoff

## 目标

继续推进 #319（不转向 #323）：共用 Whisper JSON transcript parser，安全读取 `whisperRawJsonPath`，并仅在解析结果逐项匹配已通过音频校验的内嵌第二稿时使用；缺失、异常或不匹配时回退快照。V2 先显示 metadata-only 工程证据提示；项目 revision、当前选中音频和草稿核验仍在用户确认后执行。未核对完整验收并通过质量门前，不宣称 #319 完成或关闭。

## Git 现场

分支 `arena/6929f1a1-lyric-forge-ktv`（active），基于 `48f5a75e19bdb8311f0ec7e52ceea9cc581b7985`；HEAD 仍是 `48f5a75`，尚未提交或开 PR。`#319` 当前为 OPEN，完整验收标准见 `gh issue view 319 --repo BrainEno/lyric-forge-ktv`。

`git status --short`（工作区快照；含本 handoff 与 work-log 文件）：

```text
 M docs/handoff.md
 M docs/lyric_proofreading_v2_plan.md
 M docs/reviews/2026-11-07-asr-product-followup.md
 M docs/work_log.md
 M docs/work_log_archive.md
 M docs/work_log_index.md
 M lib/app/lyric_editor_assembly.dart
 M lib/features/lyrics/domain/proofreading/project_proofread_evidence.dart
 M lib/features/lyrics/presentation/controllers/lyric_editor_proofreading_coordinator.dart
 M lib/features/lyrics/presentation/lyric_editor_dependencies.dart
 M lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart
 M lib/features/transcription/data/services/project_proofread_evidence_loader.dart
 M lib/features/transcription/data/services/whisper_cpp_transcription_service.dart
 M test/architecture/app_assembly_contract_test.dart
 M test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart
 M test/features/lyrics/presentation/widgets/proofread_v2_project_evidence_test.dart
 M test/features/transcription/project_proofread_evidence_loader_test.dart
?? docs/log/entries/2026-11-07-0001-preselect-verified-proofread-evidence.md
?? lib/features/transcription/data/services/whisper_json_artifact_reader.dart
?? lib/features/transcription/data/services/whisper_json_transcript_parser.dart
?? test/features/transcription/whisper_json_artifact_reader_test.dart
?? test/features/transcription/whisper_json_transcript_parser_test.dart
```

`git diff --stat`（不含未跟踪文件）：17 files changed, 781 insertions(+), 130 deletions(-)。
`git log --oneline -5`：

```text
48f5a75 Merge pull request #436 from BrainEno/arena/687794f2-lyric-forge-ktv
```

本轮 Dart 源码与测试共增加 1,429 行（另有 108 行删除），超过每轮 800 行要求。

## 已改文件

- `lib/features/transcription/data/services/whisper_json_transcript_parser.dart`：有界 Whisper JSON 解析与置信度映射；正式 Whisper 转写和 artifact reader 共用。
- `lib/features/transcription/data/services/whisper_json_artifact_reader.dart`：限制路径/文件字节、拒绝符号链接条目、检查文件变化并严格 UTF-8 解码。
- `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`：改用共享 parser。
- `lib/features/transcription/data/services/project_proofread_evidence_loader.dart`：新增 metadata-only `preview()`；先完成项目 revision 与音频哈希核验，再在 Whisper raw JSON 与内嵌快照逐行字段相符时使用 raw parse，否则回退快照。
- `lib/features/lyrics/domain/proofreading/project_proofread_evidence.dart`、`lib/features/lyrics/presentation/lyric_editor_dependencies.dart`、`lib/app/lyric_editor_assembly.dart`：增加 preview hint / adapter 注入。
- `lib/features/lyrics/presentation/controllers/lyric_editor_proofreading_coordinator.dart`、`lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`：先预览候选；仅当前草稿匹配候选默认选择；原稿/分片只读，并说明音频摘要缺失等不可用状态。
- 新增 parser、artifact reader 测试；扩展 loader、V2 widget、editor integration 和 assembly contract 测试。
- `docs/reviews/2026-11-07-asr-product-followup.md`、`docs/lyric_proofreading_v2_plan.md`、work-log entry/index/archive：记录范围和未验收项。

## 检查结果

- `git diff --check`：通过。
- `bash scripts/check_app_identifiers.sh`：通过。
- `dart tool/work_log.dart write` 与 `dart tool/work_log.dart check`：已尝试，均因 `/bin/bash: dart: command not found` 退出 127；工作区没有 Dart、Flutter 或 FVM SDK。
- 因无 SDK，未运行 `dart format`、`flutter analyze`、本轮新增及相关 Flutter tests、work-log harness。尚无本分支 CI 或 PR 结果；不能把它们记为通过。
- Work-log entry 已增加，archive 导航链接已补齐；待有 SDK 时实际运行 `write/check` 并审查生成 diff。

## 下一步

在固定 Flutter SDK 的验证环境中运行格式化、analyzer、相关测试及 `dart tool/work_log.dart write/check`；修复所有失败后，刷新并逐项核对 #319 的四项完整验收标准，再推送本分支、开 PR，并只在最终 head 的 Flutter Quality Gate 全绿后合并。

## 已知风险

#319 当前 OPEN。本轮仅完成工程证据读取/预览这一切片；完整验收仍需逐项核对：最高质量工程无粘贴时产生 consensus 且不含 `secondaryAsrUnavailable`、参考歌词 + ForcedAligner 的逐行 `forcedAlignment(reference)` 时间提案、被策略忽略选项的明确文案，以及独立的编排单元测试。现有代码/测试能找到相关实现，但本轮未完整复验，且所有 Flutter/Dart 检查待跑。SHA-256 和 revision 是点时检查，不是文件锁或模型内容认证；没有真实歌曲音频评测，因此不宣称识别准确率提升。

最后更新：2026-11-07（UTC）
