import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';

void main() {
  group('AsrRuntimeStatus', () {
    const profile = ResolvedTranscriptionProfile(
      profile: TranscriptionProfilePreference.intelMacHighQuality,
      label: 'Intel Mac 高质量',
      description: 'test',
      hardware: TranscriptionHardwareInfo(
        operatingSystem: 'macos',
        architecture: 'x86_64',
      ),
      config: TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        qwenExecutable: 'qwen3-asr',
        whisperExecutable: 'whisper-cli',
        modelPath: 'ggml-large-v3.bin',
      ),
    );

    test('is ready only when every required component is ready', () {
      const status = AsrRuntimeStatus(
        profile: profile,
        managedRoot: '/tmp/runtime',
        components: [
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.ffmpeg,
            state: AsrRuntimeComponentState.ready,
            label: 'FFmpeg',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperRuntime,
            state: AsrRuntimeComponentState.ready,
            label: 'Whisper',
            detail: 'ready',
          ),
        ],
      );

      expect(status.isReady, isTrue);
      expect(status.readyCount, 2);
    });

    test('missing component keeps environment not ready', () {
      const status = AsrRuntimeStatus(
        profile: profile,
        managedRoot: '/tmp/runtime',
        components: [
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.ffmpeg,
            state: AsrRuntimeComponentState.ready,
            label: 'FFmpeg',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperModel,
            state: AsrRuntimeComponentState.missing,
            label: 'Whisper model',
            detail: 'missing',
          ),
        ],
      );

      expect(status.isReady, isFalse);
      expect(status.readyCount, 1);
    });

    test('a missing second engine degrades instead of blocking', () {
      const status = AsrRuntimeStatus(
        profile: profile,
        managedRoot: '/tmp/runtime',
        components: [
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.ffmpeg,
            state: AsrRuntimeComponentState.ready,
            label: 'FFmpeg',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperRuntime,
            state: AsrRuntimeComponentState.ready,
            label: 'Whisper',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperModel,
            state: AsrRuntimeComponentState.ready,
            label: 'Whisper model',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.qwenRuntime,
            state: AsrRuntimeComponentState.missing,
            label: 'Qwen runtime',
            detail: 'missing',
          ),
        ],
      );

      // Nothing is "fully ready", but lyrics can still be produced.
      expect(status.isReady, isFalse);
      expect(status.isBaselineReady, isTrue);
      expect(status.missingBaselineComponents, isEmpty);
    });

    test('a missing Whisper baseline blocks recognition', () {
      const status = AsrRuntimeStatus(
        profile: profile,
        managedRoot: '/tmp/runtime',
        components: [
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.ffmpeg,
            state: AsrRuntimeComponentState.ready,
            label: 'FFmpeg',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperModel,
            state: AsrRuntimeComponentState.missing,
            label: 'Whisper model',
            detail: 'missing',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.qwenRuntime,
            state: AsrRuntimeComponentState.ready,
            label: 'Qwen runtime',
            detail: 'ready',
          ),
        ],
      );

      expect(status.isBaselineReady, isFalse);
      expect(
        status.missingBaselineComponents.map((c) => c.component),
        [AsrRuntimeComponent.whisperModel],
      );
    });
  });
}
