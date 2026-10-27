# Handoff

## 目标
让最高质量本地 ASR 在单次双引擎识别中只进行一次 FFmpeg 标准化，Qwen 与 Whisper 消费完全相同的 16 kHz、单声道、signed 16-bit PCM WAV；不引入跨任务缓存，并保障取消和失败时清理不完整产物。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 分支：`feat/shared-normalized-asr-input-20261027`
- PR：[#204 perf: share normalized audio between ASR engines](https://github.com/BrainEno/lyric-forge-ktv/pull/204)
- main 基线：`df0d4940cda23151ad3b641e693944d78c4be522`（PR #203 合并后）
- 业务实现代码及格式/路径安全修正：`5a7bc73495d223928702dba5ca349ea33549f016`
- 本次工作日志与文档更新作为独立提交；需以该文档提交之后的最新 PR head CI 状态为最终验证。
- 当前执行环境没有 Dart/Flutter SDK；依赖 GitHub Actions 完成格式、分析和测试。

## 已改文件
- `lib/features/transcription/domain/models/transcription_models.dart`
- `lib/features/transcription/data/services/high_quality_transcription_service.dart`
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`
- `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`
- `test/high_quality_transcription_service_test.dart`
- `docs/high_quality_asr.md`
- `docs/local_transcription.md`
- `docs/log/entries/2026-10-27-1920-share-normalized-asr-input.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 给 `TranscriptionRequest` 增加可选 `normalizedInputAudioPath`，让上层明确传入已标准化文件。
- 最高质量模式在任务输出目录创建 `high_quality_shared_input.wav`；每次新任务重建，不做跨任务缓存。
- 在 Qwen-primary 与 Whisper-primary 两种顺序中，将同一标准化路径传给两个引擎；适配器在拿到该路径时跳过重复 FFmpeg 转换，普通单引擎调用仍沿用既有预处理。
- 跟踪共享 FFmpeg 进程，使取消可以终止生成；失败/取消会删除不完整 WAV，成功文件则保留以保证 `normalizedAudioPath` 仍然有效。
- 加入防护：若共享输出路径等于源音频路径，直接报错而不删除输入文件。
- 为两种引擎顺序新增编排回归测试，验证标准化回调只运行一次，且两个服务拿到同一个路径。

## 检查结果
- 初始代码 head 的 Flutter Quality Gate 只在 Dart format 检查处失败；根据 CI 返回的精确差异修正格式，并在源/输出路径重合时加入安全保护。
- 格式修正代码 head `5a7bc73495d223928702dba5ca349ea33549f016` 的 CI 已触发；以文档提交之后最新 PR head 的最终完成状态为准。
- 本执行环境未运行本地 `dart format`、`flutter analyze` 或 `flutter test`；未声称真实歌曲识别率提高。

## 下一步
检查 PR #204 最新 head 的 Flutter Quality Gate、ASR client checks、Transcription settings validation、Transcription execution failure validation 和 queue protective pause validation。若出现编译/测试失败，先依据具体日志修复，不靠重复重跑掩盖问题。

## 已知风险
- 共享 WAV 每任务保留在项目输出目录中，因为识别结果和项目元数据会引用该路径；下一次相同输出目录上的最高质量任务会先删除并重建它。
- FFmpeg 默认音轨选择策略未改变，多音轨选择仍需实曲验证。
- 同一输入文件消除了两套引擎预处理不同这一干扰因素，但并不等于歌词召回率、WER 或时间对齐精度必然提高。
- 真实 Windows + RTX 5080 环境仍需端到端验证取消行为、输出文件生命周期及实曲效果。

最后更新：2026-10-27 19:20（Asia/Taipei）
