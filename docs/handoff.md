# Handoff

## 目标
修复最高质量 ASR 的模型身份元数据：融合结果和项目持久化记录必须反映配置中实际指定的 Qwen ASR、Qwen ForcedAligner、Whisper 模型，而不能把模型版本固定写成 1.7B、0.6B 或 large-v3。模型标签只存路径末级名称，避免把本机绝对目录写进项目元数据。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`fix/asr-model-provenance-20261027`
- PR：[#202 fix: persist actual ASR model identities](https://github.com/BrainEno/lyric-forge-ktv/pull/202)
- main 基线：`9218d6d4811d45d2043c3b0039640f880724ad2f`（PR #201 合并后的 main）
- 代码验证 head：`7f288d7a03d9c21e4120f604e915e226bdb5d12a`
- 本文档只更新验证和交接状态，不改业务代码。
- 当前执行环境没有 Dart/Flutter SDK；格式、分析与测试通过 GitHub Actions Flutter Quality Gate 和专项工作流执行。

## 已改文件
- `lib/features/transcription/domain/models/transcription_model_identity.dart`
- `lib/features/transcription/data/services/high_quality_transcription_service.dart`
- `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- `test/features/transcription/transcription_model_identity_test.dart`
- `test/high_quality_transcription_service_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-1754-derive-asr-model-identities.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 新增 `TranscriptionModelIdentity`，从模型配置路径推导稳定的 engine key 与可读标签。
- 修复 Qwen 主识别、Whisper 主识别两种融合路径的成功/失败元数据，不再硬编码模型大小或默认 Whisper 版本。
- 修复项目转写元数据中的 `primaryModel`、`alignmentModel`、`fallbackModel`，让标签来自解析后的运行配置。
- 覆盖 Qwen ASR 0.6B/1.7B、非默认 1.5B ForcedAligner、Whisper medium/large-v3、自定义 Windows 路径以及融合服务元数据。
- 文档明确说明：路径标签不能证明运行时实际加载的权重版本，也不是权重文件哈希。

## 检查结果
在代码验证 head `7f288d7a03d9c21e4120f604e915e226bdb5d12a` 上：
- Flutter Quality Gate run [40485581600](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40485581600)：通过；work-log preflight、依赖解析、Dart 格式检查、仓库质量门均成功；`flutter test` 报告 746 tests passed。
- ASR client checks run [40485581638](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40485581638)：通过。
- Transcription queue protective pause run [40485581625](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40485581625)：通过；专项检查成功，完整回归测试 746 tests passed。
- Transcription settings validation run [40485581696](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40485581696)：通过；设置契约与完整回归测试成功。
- 本地未运行 Dart/Flutter 命令；上述结果均来自 GitHub Actions。
- 未宣称真实歌曲 WER、歌词召回率或时间精度提升；本次修复的是模型元数据与来源可追溯性。

## 下一步
复核这次交接文档更新后触发的最新 PR 检查；若质量门继续通过，PR #202 可供维护者合并。合并后再进入下一项独立任务：审查 Qwen/Whisper 是否对同一来源音频使用一致的 FFmpeg 预处理，并继续评估本地人声分离后端。

## 已知风险
- 模型身份依赖配置路径最后一段；自定义目录名不一定是真实模型 revision。
- 尚未记录运行时实际加载权重的哈希，也未在此工作流里验证 native runtime 装载的 revision。
- 合成测试验证元数据契约，不证明中英日真实歌曲的识别准确率。
- 两个 ASR adapter 的 FFmpeg 预处理及 Windows 原生运行链路仍需在实际机器上做端到端验证。

最后更新：2026-10-27 18:06（Asia/Taipei）
