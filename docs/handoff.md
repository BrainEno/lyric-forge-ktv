# Handoff

## 目标
继续完成歌词智能校对 V2 的安全任意文本 ForcedAligner 路径：原生 endpoint 已合并并通过 CI；本轮已新增 Dart orchestration service，并将其接入歌词编辑器的 ASR-first 校对流程：用户可显式启用词级时间证据，界面会显示覆盖率或运行时降级提示。

## Git 现场
- 基线：PR #184 已合并，包含 pinned Rust/Candle sidecar 的 `POST /v1/align` endpoint 与 Windows CUDA/macOS Intel 原生构建修复。
- 当前开发分支：`feat/forced-align-proofread-service-20261025`，基于最新 main。
- 固定 Qwen 源码 revision：`7984967e8701cc90bb17d06453901036e36ca578`。
- 当前分支 `feat/forced-align-proofread-service-20261025` 已包含 service、Qwen managed runtime runner、编辑器开关和回归测试；等待最新 head 的远端 CI。
- 当前执行环境没有本地仓库 checkout 或 Dart/Flutter SDK，不能声称本地格式化、分析或测试通过。

## 已改文件
- `lib/features/transcription/data/services/forced_alignment_proofread_service.dart`
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`
- `lib/core/services/service_locator.dart`
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`
- `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`
- `test/features/transcription/forced_alignment_proofread_service_test.dart`
- `docs/high_quality_asr.md`
- `docs/handoff.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/log/entries/2026-10-25-2155-wire-forced-align-proofread-service.md`

## 本轮实现
- service 显式要求 audio path、reference lyric text、language、audio duration。
- 成功时将 client spans 转为 `ProofreadAlignmentSpan`，复用 `AsrFirstPipeline` 匹配并生成低置信度的 forced-aligner review tokens。
- 覆盖不完整时返回逐行复核 warning；endpoint/response 失败时仍生成常规 review proposal，并附加 `forcedAlignmentUnavailable` note。
- 绝不自动应用歌词文本或行级时间戳。成功和失败路径都保留源歌词与源时间。
- 新增测试覆盖成功映射、无匹配行提示、endpoint 失败降级、managed runner 路径和 UI opt-in 控件。
- Qwen service 通过同一 managed native server 调用 `/v1/align`，用 FFmpeg 将音频规范化到 16 kHz 单声道 WAV，并清理临时文件。
- 编辑器先检查 runtime 与 aligner readiness；运行时错误由 service 降级为普通 ASR-first 提案，并显示警告。

## 检查结果
- 前置 PR #184 的 native runtime CI、Flutter Quality Gate 与 release contract 已通过。
- 本轮需要远端 Flutter Quality Gate 验证新增代码；尚未验证真实歌曲的对齐质量。
- 即使 endpoint 已合并，用户已有的 runtime bundle 仍可能不含该 endpoint，需安装重新构建的 bundle。

## 下一步
- 等待最新 head 的 Flutter Quality Gate、ASR client checks 与 transcription settings validation；如失败，按实际日志修复，不绕过测试。
- CI 通过后，检查逐行 UI 是否能清晰区分有 token 证据与缺失证据；再推进中、英、日真实音轨验收和逐行试听/确认闭环。
- 用中文、英文、日文音轨验证覆盖率、单调时间和音频边界；异常结果只进入人工复核，不自动改写。
- 再推进逐行试听与确认/撤销闭环。

## 已知风险
- UI 集成和 managed runner 尚待远端 CI 验证；运行时 endpoint 仅在安装含 `/v1/align` 的新 bundle 后可用。
- CI contract test 不代表真实模型的时间戳精度已通过验收。
- 真实音频验收仍需在 Windows RTX 5080 目标机执行。

最后更新：2026-10-26 14:00（Asia/Taipei）
