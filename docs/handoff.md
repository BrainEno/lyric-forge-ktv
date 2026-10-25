# Handoff

## 目标
为歌词智能校对 V2 建立可验证的任意文本 ForcedAligner 调用契约，后续再将其接入 reference-first / ASR-first 的时间提案。不得将 ASR 的 context 提示冒充强制对齐，也不得在时间证据不安全时自动改写歌词。

## Git 现场
- 基线：main 已合并 PR #179（ASR-first 第二份带时间戳转写输入）。
- 工作分支：feat/forced-aligner-http-adapter-contract-20261025。
- 本次改动通过独立 PR 提交；main 不直接写入功能变更。
- 当前执行环境没有本地 repository checkout，也没有 Dart/Flutter 执行文件；远端 GitHub Actions 用作代码质量门禁。

## 本轮实现
- lib/features/transcription/data/services/forced_alignment_http_client.dart：新增显式 HTTP 强制对齐客户端，调用方必须提供 endpoint，发送 audio/text/language；不默认调用 /v1/transcribe。
- test/features/transcription/forced_alignment_http_client_test.dart：覆盖请求合同、嵌套结果解析、HTTP 错误、空输入、非单调时间戳与音频边界。
- docs/high_quality_asr.md：记录官方 Qwen Python API 支持 audio + text + language，但现有 Rust/Candle sidecar 只验证了转写接口，不能据此宣称现有端点支持任意文本对齐。

## 检查结果
- 远程 CI 需验证格式、静态分析、全量 Flutter 测试与 work-log lint。
- 本环境未运行 dart format、flutter analyze、定向测试或 dart run tool/work_log.dart check。
- 新客户端是可测试的适配器边界，不代表当前 sidecar 已提供 /v1/align；尚未接入生产流程。

## 下一步
- 在固定版本的 Rust/Candle runtime 上实现或提供独立的本地 align bridge，并在 Windows CUDA 与 macOS CI 中验证。
- 接入时验证输出文本覆盖、时间单调性、非负值与音频边界；不合格结果只能作为复核警告，不能写入歌词。
- 随后将安全的对齐结果接入 proofread review proposal，保留用户确认与撤销边界。

## 已知风险
- 当前 qwen3-asr-rs sidecar 的 /v1/transcribe 请求不接收指定文本；此 PR 不会伪造该能力。
- 实际模型对整首歌曲和歌词片段的对齐质量仍需在 Windows + RTX 5080 上用真实歌曲验收。
- 真实行试听、窗口尺寸矩阵以及应用后撤销仍需手动验收。

最后更新：2026-10-25 16:10（Asia/Taipei）
