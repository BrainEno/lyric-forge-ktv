# Handoff

## 目标
为歌词智能校对 V2 建立安全的任意文本 ForcedAligner 路径。已经完成 HTTP 客户端合同，并把经验证的时间跨度接入 ASR-first 复核提案作为 token 级证据；下一步仍需给固定版本 Rust/Candle sidecar 增加真实任意文本对齐端点，再通过真实音频验证。

## Git 现场
- 基线：main 已合并 PR #179（第二份带时间戳 ASR 输入）、PR #180（显式 ForcedAligner HTTP 客户端合同）及 PR #181（收紧原生 ASR 构建触发条件）。
- 当前分支：feat/forced-alignment-proofread-evidence-20261025。
- 当前改动独立提交到 PR，不直接写 main。
- 执行环境没有本地 repository checkout，也没有 Dart/Flutter 执行文件；使用远端 GitHub Actions 做质量门禁。

## 已改文件
- `lib/features/lyrics/domain/proofreading/proofread_result.dart`
- `lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart`
- `test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart`
- `docs/high_quality_asr.md`
- `docs/handoff.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/log/entries/2026-10-25-1705-forced-alignment-evidence-proposals.md`

## 本轮实现
- 定义经过验证的 `ProofreadAlignmentSpan` 输入类型。
- ASR-first pipeline 接受可选对齐跨度，按源顺序将连续 token 文本与每行歌词做保守匹配；匹配成功后以置信度 60、`forcedAligner` 来源附加到该行的 `TimedLyricToken` 列表。
- 时间跨度必须按 start 排序，且不能超出已知音频时长；未匹配歌词增加 `noTimingEvidence` 并保持 amber 复核状态。
- 不改变歌词文本、行级起止时间或持久化文档。

## 检查结果
- 新增测试覆盖 token 匹配、标点/空白归一化、未匹配行、音频边界和乱序拒绝。
- 远端 CI 尚待验证格式、静态分析、全量 Flutter 测试及 work-log lint。
- 未运行本地 Dart/Flutter 命令。

## 下一步
- 在固定 Qwen Rust/Candle commit 上实现独立的 `POST /v1/align`，入参明确为 audio、text、language，复用已加载 ForcedAligner，不得把 `context` 当成目标文本。
- 更新 Windows/macOS runtime build workflow 以应用并测试该 patch；由于原生构建已按原生输入过滤，Dart-only PR 不应再重复构建 CUDA/Intel runtime。
- 在真实歌曲上验证中文、英文、日文混合文本覆盖和 token 时间质量；只有通过质量门槛的跨度才可进入复核提案。
- 后续接入 UI 的试听、逐行接受、撤销流程；未获用户确认前不应用歌词改动。

## 已知风险
- 当前 sidecar 的 `/v1/transcribe` 不接收指定歌词文本，不能直接完成 reference-first 任意文本对齐。
- 文本匹配目前要求每行能由连续对齐跨度完整覆盖；未覆盖或 tokenization 不一致时会保守地标记缺少证据，而不是猜测匹配。
- 模型实际对齐精度仍需 Windows + RTX 5080 真实音频验收。

最后更新：2026-10-25 17:05（Asia/Taipei）
