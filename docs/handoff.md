# Handoff

## 目标
为歌词智能校对 V2 建立安全的任意文本 ForcedAligner 路径。HTTP 客户端合同和 ASR-first 复核提案中的 token 证据已合并；本轮为固定版本 Rust/Candle sidecar 添加独立的 `POST /v1/align` patch，并让原生 runtime 构建应用该 patch。

## Git 现场
- 基线：main 已合并 PR #179、#180、#181、#182。
- 当前分支：`feat/qwen-forced-align-http-endpoint-20261025`。
- 固定 Qwen 源码 revision：`7984967e8701cc90bb17d06453901036e36ca578`。
- 当前改动独立 PR；native build 和 Flutter CI 仍待远端验证。
- 本执行环境没有本地仓库 checkout、Rust toolchain 或 Dart/Flutter SDK；不能声称本地编译/测试通过。

## 已改文件
- `tool/patches/qwen3-asr-forced-align-http-endpoint.patch`
- `.github/workflows/build-asr-runtime.yml`
- `docs/high_quality_asr.md`
- `docs/high_quality_asr_windows_setup.md`
- `docs/handoff.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/log/entries/2026-10-25-1948-add-native-forced-align-endpoint.md`

## 本轮实现
- 固定 Rust/Candle source patch 增加 `POST /v1/align`，请求为 `audio`、`text`、`language`；调用已加载的 `Qwen3ForcedAligner.align`，响应采用 `results[0].items`，每项提供 `text`、`start_time`、`end_time`（秒）。
- 端点不把 `context` 当成目标歌词，不调用 `/v1/transcribe` 来伪装对齐。
- 请求字段为空时返回 400；mock server integration test 覆盖三种必填字段校验和根端点列表。
- Windows CUDA 与 macOS Intel 原生构建均应用 patch；macOS Intel CI 增加 endpoint contract integration test。runtime manifest patch revision 同步更新。
- 原生 patch 输入位于 `tool/patches/**`，因此会触发昂贵的 native build；普通 Dart-only 修改仍不会触发该构建。

## 检查结果
- 已审查 pinned source：其 `Qwen3ForcedAligner` 暴露公开的 `align(audio, text, language)` API，原 server 已有单 worker 串行化模型访问机制。
- 已静态核对 patch hunks 的上下文顺序与行数，但由于当前环境无法访问外部网络/运行 Rust，尚未在本地执行 `git apply --check` 或 cargo test。
- 必须等待远端 CI 验证 patch 可应用、Windows/macOS runtime 可编译、endpoint integration test 通过，以及 Flutter/work-log 质量门通过。

## 下一步
- 如 native patch 或编译失败，按 pinned revision 的真实编译日志修复，不要先把 endpoint 宣称为可用。
- CI 通过后，将 `ForcedAlignmentHttpClient` 接入实际复核用例，明确提供音频路径、参考歌词和语言；继续复用已合并的 `ProofreadAlignmentSpan` 证据映射。
- 再用中文、英文、日文歌曲验证覆盖率、时间单调性和音频边界；任何不完整/异常结果只能标记复核，不自动改写歌词。
- 后续推进逐行试听、用户确认与撤销闭环。

## 已知风险
- 本轮端点 patch 尚未经过远端 native build 验证；旧 runtime bundle 不会自动包含新 endpoint。
- 合同测试验证请求字段与 endpoint discovery，不代表真实模型对齐质量已通过。
- 真实音频精度仍需在 Windows RTX 5080 目标机上验收。

最后更新：2026-10-25 19:48（Asia/Taipei）
