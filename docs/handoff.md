# Handoff

## 目标
修复最高质量 ASR 的模型身份元数据：融合结果和项目持久化记录必须反映配置中实际指定的 Qwen ASR、Qwen ForcedAligner、Whisper 模型，而不能把模型版本固定写成 1.7B、0.6B 或 large-v3。模型标签只存路径末级名称，避免把本机绝对目录写进项目元数据。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`fix/asr-model-provenance-20261027`
- PR：[#202 fix: persist actual ASR model identities](https://github.com/BrainEno/lyric-forge-ktv/pull/202)
- main 基线：`9218d6d4811d45d2043c3b0039640f880724ad2f`（合并 PR #201 后的 main）
- 本次 handoff 更新前的分支 head：`f6406ce7384bd61bcbedfa535a302635acfdaf68`；本文档是本次最后一项待提交更改。
- 当前执行环境无 Dart/Flutter SDK；使用 GitHub Actions Flutter Quality Gate 检查格式、分析、工作日志契约与完整测试。

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
- 新增 `TranscriptionModelIdentity`，从模型配置路径推导稳定的 engine key 与人类可读标签。
- 修复 Qwen 主识别、Whisper 主识别两种融合路径的成功/失败元数据，不再硬编码模型大小或默认 Whisper 版本。
- 修复项目转写元数据中的 `primaryModel`、`alignmentModel`、`fallbackModel`，让标签来自已解析的运行配置。
- 覆盖 Qwen ASR 0.6B/1.7B、非默认 1.5B ForcedAligner、Whisper medium/large-v3、自定义 Windows 路径以及服务融合元数据。
- 文档明确说明：路径标签不能证明运行时实际加载的权重版本，也不是权重文件哈希。

## 检查结果
- 新增单元测试；PR #202 的最新 head 必须以 GitHub Actions Flutter Quality Gate 最终结果为准。
- 当前执行环境无法本地运行 `dart format`、`flutter analyze` 或 `flutter test`；没有将这些检查标注为已通过。
- 未宣称真实歌曲 WER、歌词召回率或时间精度提升；本次修复的是模型元数据与来源可追溯性。

## 下一步
检查 PR #202 最新 head 的质量门；若格式、分析或测试失败，先按失败日志修复并确认新 head 的结果。通过后由仓库维护流程合并，再继续审查“同一原始音频是否被两个引擎以一致预处理输入处理”和人声分离后端的主线工作。

## 已知风险
- 模型身份依赖配置路径最后一段；自定义目录名不一定是真实模型 revision。
- 尚未记录被加载权重文件的哈希，也未在此工作流里验证 runtime bundle 实际装载的 revision。
- 合成测试验证元数据契约，不证明中英日真实歌曲的识别准确率。
- 两个 ASR adapter 的 FFmpeg 预处理及 Windows 原生运行链路仍需在实际机器上验证。

最后更新：2026-10-27 17:54（Asia/Taipei）
