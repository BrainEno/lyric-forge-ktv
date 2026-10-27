# Handoff

## 目标
让最高质量本地 ASR 在单次双引擎识别中只进行一次 FFmpeg 标准化，Qwen 与 Whisper 消费完全相同的 16 kHz、单声道、signed 16-bit PCM WAV；不引入跨任务缓存，并在取消/失败时尽力清理不完整产物。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 分支：`feat/shared-normalized-asr-input-20261027`
- PR：[#204 perf: share normalized audio between ASR engines](https://github.com/BrainEno/lyric-forge-ktv/pull/204)
- main 基线：`df0d4940cda23151ad3b641e693944d78c4be522`（PR #203 合并后）
- 已验证实现/主要文档 head：`96e8f2c4c46d8e57262451da0a155be04d245741`
- 此后本次工作只记录 CI 结果并微调失败清理措辞；最终文档提交之后仍需确认新 head workflow。
- 当前执行环境没有 Dart/Flutter SDK；验证由 GitHub Actions 执行。

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
- 跟踪共享 FFmpeg 进程，使取消可以终止生成；失败/取消时尝试删除不完整 WAV，成功文件则保留以保证 `normalizedAudioPath` 仍然有效。
- 加入防护：若共享输出路径等于源音频路径，直接报错而不删除输入文件。
- 为两种引擎顺序新增编排回归测试，验证标准化回调只运行一次，且两个服务拿到同一个路径。

## 检查结果
在实现/主要文档 head `96e8f2c4c46d8e57262451da0a155be04d245741` 上：
- Flutter Quality Gate run [40496005845](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005845)：work-log preflight 和 Dart format check 通过；`flutter analyze lib test` 通过；`flutter test` 报告 752 tests passed；repository quality gate passed。
- ASR client checks run [40496005889](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005889)：通过。
- Transcription settings validation run [40496005834](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005834)：通过，包括 settings/store contract 与完整 Flutter regression suite。
- Transcription execution failure validation run [40496005839](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005839)：通过，包括完整 Flutter regression suite。
- Transcription queue protective pause validation run [40496006747](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496006747)：通过，包括完整 Flutter regression suite。
- 初始 CI 曾报 Dart format 差异，随后根据远端 formatter 的 diff 修正；此后通过的质量门使用干净格式结果。
- 本地未运行 Dart/Flutter 命令；没有声称真实歌曲识别率获得提升。

## 下一步
确认本次记录验证结果的文档提交所触发的最新 PR #204 checks 完成。所有代码与完整测试已在前一个实现/主要文档 head 通过；如果只剩文档提交导致的问题，先检查 work-log lint 与 Markdown 文件。

## 已知风险
- 共享 WAV 每任务保留在项目输出目录中，因为识别结果和项目元数据会引用该路径；下一次相同输出目录上的最高质量任务会先删除并重建它。
- 不完整文件删除是尽力清理；如操作系统或文件占用导致删除失败，可能残留文件。
- FFmpeg 默认音轨选择策略未改变，多音轨选择仍需实曲验证。
- 同一输入文件消除了两套引擎预处理不同这一干扰因素，但并不等于歌词召回率、WER 或时间对齐精度必然提高。
- 真实 Windows + RTX 5080 环境仍需端到端验证取消行为、输出文件生命周期及实曲效果。

最后更新：2026-10-27 19:28（Asia/Taipei）
