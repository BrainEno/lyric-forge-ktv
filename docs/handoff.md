# Handoff

## 目标
继续完成歌词智能校对 V2 的安全任意文本 ForcedAligner 路径：原生 endpoint 已合并并通过 CI；本轮新增 Dart orchestration service，将验证后的对齐结果作为 review-only token evidence 注入 ASR-first proposal。

## Git 现场
- 基线：PR #184 已合并，包含 pinned Rust/Candle sidecar 的 `POST /v1/align` endpoint 与 Windows CUDA/macOS Intel 原生构建修复。
- 当前开发分支：`feat/forced-align-proofread-service-20261025`，基于最新 main。
- 固定 Qwen 源码 revision：`7984967e8701cc90bb17d06453901036e36ca578`。
- 当前改动新增 `ForcedAlignmentProofreadService` 及对应 HTTP-server tests；PR CI 待验证。
- 当前执行环境没有本地仓库 checkout 或 Dart/Flutter SDK，不能声称本地格式化、分析或测试通过。

## 本轮实现
- service 显式要求 audio path、reference lyric text、language、audio duration。
- 成功时将 client spans 转为 `ProofreadAlignmentSpan`，复用 `AsrFirstPipeline` 匹配并生成低置信度的 forced-aligner review tokens。
- 覆盖不完整时返回逐行复核 warning；endpoint/response 失败时仍生成常规 review proposal，并附加 `forcedAlignmentUnavailable` note。
- 绝不自动应用歌词文本或行级时间戳。成功和失败路径都保留源歌词与源时间。
- 新增测试覆盖成功映射、无匹配行提示、endpoint 失败降级。

## 检查结果
- 前置 PR #184 的 native runtime CI、Flutter Quality Gate 与 release contract 已通过。
- 本轮需要远端 Flutter Quality Gate 验证新增代码；尚未验证真实歌曲的对齐质量。
- 即使 endpoint 已合并，用户已有的 runtime bundle 仍可能不含该 endpoint，需安装重新构建的 bundle。

## 下一步
- 等待本轮 CI；如失败，按实际日志修复，不绕过测试。
- CI 通过后，下一阶段为把该 service 接入实际 proofread UI/use case，并提供可见的运行时不可用/覆盖率提示。
- 用中文、英文、日文音轨验证覆盖率、单调时间和音频边界；异常结果只进入人工复核，不自动改写。
- 再推进逐行试听与确认/撤销闭环。

## 已知风险
- 当前 service 尚未接入用户可见 UI，因此本轮只建立可测试的 orchestration boundary。
- CI contract test 不代表真实模型的时间戳精度已通过验收。
- 真实音频验收仍需在 Windows RTX 5080 目标机执行。

最后更新：2026-10-25 22:00（Asia/Taipei）
