# Handoff

## 目标

完成 Issue #321：统一 ASR 转录管线的结构化取消语义，彻底移除对 `error.message == '歌词识别已取消'` 的控制流字符串匹配，收敛到 `TranscriptionFailureKind.cancelled`（`TranscriptionException.isCancelled`），并补齐双引擎顺序、分片续跑、工程工作流、队列联动与静态防回退回归测试。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/50826e2d-lyric-forge-ktv`（Arena 会话固定工作分支）
- 基线：`a0dbdabdc841fe8114b69b9e4f45ee6619513969`（`main`）
- 关联 Issue：https://github.com/BrainEno/lyric-forge-ktv/issues/321（保持 OPEN，不在 PR 中自动关闭）
- 最新提交：`367ac2a65089c25a94bfb4c35f9eb61750e4a3fe`，标题 `fix: unify ASR pipeline typed cancellation`
- PR：https://github.com/BrainEno/lyric-forge-ktv/pull/367（OPEN）

## 已改文件

- `lib/features/transcription/domain/models/transcription_models.dart`：在 `TranscriptionException` 新增 `bool get isCancelled => kind == TranscriptionFailureKind.cancelled`。
- `lib/features/transcription/data/services/high_quality_transcription_service.dart`：将内部 `_HighQualityCancelledException` 转为 `TranscriptionException.cancelled('歌词识别已取消')`；替换全部基于文案的取消判断与降级判定，确保 Qwen-primary / Whisper-primary 主备取消均原样传播且不触发降级。
- `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`：移除分片重试中的文案匹配兜底，遇到结构化取消立即终止且保留已完成分片检查点，统一由外层发出一次 `TranscriptionStage.cancelled`。
- `lib/features/transcription/data/services/local_project_transcription_workflow.dart`：预检与主转录异常分支统一按 `error.isCancelled` 恢复 `ready`/`editing`/`draft` 状态，保留原有歌词且不写 `metadata['transcriptionError']`。
- `lib/features/transcription/data/services/file_batch_transcription_queue.dart`：在 `_isEnvironmentBlocked` 中优先排除 `error.isCancelled`，防止含环境关键词文案的取消异常误触发队列保护性暂停。
- `test/high_quality_transcription_service_test.dart`：新增双引擎两种顺序的主/次引擎取消、内部 `cancel()`、自定义文案及 `unknown` 同名文案负向测试。
- `test/resumable_chunked_transcription_service_test.dart`：新增自定义文案取消不重试、检查点保留续跑与 `unknown` 负向测试。
- `test/features/transcription/local_project_transcription_workflow_test.dart`：新增工程工作流取消恢复 `editing`/`ready`/`draft`、保留歌词、队列联动与 `unknown` 负向测试。
- `test/features/transcription/transcription_execution_failure_kind_test.dart`：新增 `isCancelled` 单测、分片 `cancelled` 传播测试及扫描 `lib/` 禁止取消文案控制流匹配的静态契约测试。
- `docs/log/entries/2026-11-07-1535-unify-asr-typed-cancellation.md`、`docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`、`docs/handoff.md`：工作日志与交接记录。

## 检查结果

- `bash ./scripts/check_app_identifiers.sh` 与 `git diff --check` 本地通过。
- 本地容器未安装 Flutter/Dart SDK，因此未在本地直接运行 `dart format`、`flutter analyze`、`dart tool/work_log.dart check` 与 `flutter test`。
- PR head `367ac2a65089c25a94bfb4c35f9eb61750e4a3fe` 的 `Flutter Quality Gate`（[run 42353781288](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/42353781288)）及 `Transcription Queue Protective Pause Validation`（[run 42353781206](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/42353781206)）均通过；文档同步提交后须在新最终 head 再次确认。

## 下一步

1. 将本次 CI 通过结果同步到工作日志与交接文档，提交并推送到固定分支。
2. 核对文档同步后的最终 head 上 `Flutter Quality Gate` 与 `Transcription Queue Protective Pause Validation` 均通过。
3. 保持 PR #367 与 Issue #321 为 OPEN，等待维护者审阅。

## 已知风险

- ASR 运行时安装器（`managed_asr_runtime_manager.dart`、`resilient_asr_runtime_manager.dart`、`retrying_asr_runtime_manager.dart`）的安装取消仍使用独立的 `'识别环境安装已取消'` 流程，不在本轮转录管线修改范围内，后续可单独切片收敛。
- 本地无 Flutter/Dart SDK，格式、静态分析与单测回归完全依赖 GitHub Actions 固定版本环境验证。

最后更新：2026-11-07 16:05（Asia/Taipei）
