# Handoff

## 目标
防止 Qwen、Whisper 和长音频分片三条本地 ASR 路径的 FFmpeg 输出归一化参数发生漂移。统一 16 kHz、单声道、signed 16-bit PCM WAV 的参数来源，同时保留现有音频流选择和分片 seek/duration 行为。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`fix/shared-asr-audio-normalization-20261027`
- PR：[#203 refactor: unify ASR audio normalization](https://github.com/BrainEno/lyric-forge-ktv/pull/203)
- main 基线：`345dfb1b940945ecd4baf31c89449affcd7356f5`（PR #202 合并后的 main）
- 业务代码验证 head：`394f4e21cd7eb6a21673fe1a66fe5ff49b301c8a`
- 之后提交只更新工作日志、索引及交接文档；这些文档提交仍需检查最新 head 的质量门。
- 当前执行环境没有 Dart/Flutter SDK；验证由 GitHub Actions 执行。

## 已改文件
- `lib/features/transcription/data/services/asr_audio_normalization.dart`
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`
- `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`
- `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`
- `test/features/transcription/asr_audio_normalization_test.dart`
- `docs/high_quality_asr.md`
- `docs/local_transcription.md`
- `docs/log/entries/2026-10-27-1854-unify-asr-audio-normalization.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 新增 `AsrAudioNormalization` 作为唯一的输出格式参数来源。
- Qwen、Whisper 全音频预处理都调用 `ffmpegArguments`，不再在两个适配器里复制 16 kHz、mono、`pcm_s16le` 参数。
- `ResumableChunkedTranscriptionService` 调用 `chunkArguments`；它保留 `-ss` 和 `-t`，并复用相同 PCM 输出选项。
- 回归测试覆盖 Windows 路径中的空格、两个引擎不同的输出路径、分片 seek/duration、毫秒精度以及统一的输出参数后缀。
- 文档明确说明此处统一的是 FFmpeg 参数契约；全曲两条引擎仍各自转换一次，不会因此自动复用同一份 WAV。

## 检查结果
在代码 head `394f4e21cd7eb6a21673fe1a66fe5ff49b301c8a` 上：
- Flutter Quality Gate run [40491807971](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807971)：工作日志预检、Dart 格式检查通过；仓库质量门通过；`flutter test` 报告 751 tests passed。
- ASR client checks run [40491807965](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807965)：通过。
- Transcription settings validation run [40491807895](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807895)：通过，完整回归通过。
- Transcription execution failure validation run [40491807959](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807959)：通过，完整回归报告 751 tests passed。
- 本地没有运行 Dart/Flutter 命令；没有声称歌词识别准确率获得提升。

## 下一步
复核 PR #203 最新 head 的质量门。通过后供维护者合并。下一项可单独评估是否引入一次性共享标准化 WAV 供两个引擎共用；实施前需设计缓存键、音频文件变更检测、取消行为和中间文件生命周期，避免额外占用磁盘或使用陈旧音频。

## 已知风险
- FFmpeg 仍采用当前默认音频流选择策略，没有新增多音轨选择 UI，也没有改变默认流映射。
- Qwen 与 Whisper 仍分别执行转换；本次只保证参数列表一致，不证明两份输出 WAV 的字节级相同。
- 真实 Windows 本地运行、不同封装格式和多音轨文件仍需端到端验证。
- 该改动规范预处理契约，不证明 WER、歌词召回率或时间对齐精度提升。

最后更新：2026-10-27 18:54（Asia/Taipei）
