import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_runtime_health_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';

void main() {
  test('clearCache forces a real probe even when the file fingerprint is unchanged',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-health-reset-');
    addTearDown(() => root.delete(recursive: true));
    final bin = Directory('${root.path}${Platform.pathSeparator}bundle${Platform.pathSeparator}bin');
    await bin.create(recursive: true);
    final executable = File('${bin.path}${Platform.pathSeparator}qwen3-asr.exe');
    await executable.writeAsString('same-runtime-bytes');

    var probes = 0;
    final checker = LocalAsrRuntimeHealthChecker(
      probe: (_, component) async {
        if (component == AsrRuntimeComponent.qwenRuntime) probes += 1;
        return const RuntimeExecutableHealth(healthy: true, detail: 'ok');
      },
    );
    final status = AsrRuntimeStatus(
      profile: _profile(),
      managedRoot: root.path,
      components: [
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.qwenRuntime,
          state: AsrRuntimeComponentState.ready,
          label: 'Qwen runtime',
          detail: 'ready',
          resolvedPath: executable.path,
        ),
      ],
    );

    expect((await checker.verify(status)).isReady, isTrue);
    expect((await checker.verify(status)).isReady, isTrue);
    expect(probes, 1);
    expect(
      await File('${root.path}${Platform.pathSeparator}.runtime-health-v1.json').exists(),
      isTrue,
    );

    checker.clearCache();
    expect(
      await File('${root.path}${Platform.pathSeparator}.runtime-health-v1.json').exists(),
      isFalse,
    );
    expect((await checker.verify(status)).isReady, isTrue);
    expect(probes, 2);
  });
}

ResolvedTranscriptionProfile _profile() {
  const config = TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
    qwenExecutable: 'qwen3-asr.exe',
    whisperExecutable: 'whisper-cli.exe',
    modelPath: 'ggml-large-v3.bin',
  );
  return const ResolvedTranscriptionProfile(
    profile: TranscriptionProfilePreference.rtx5080HighQuality,
    label: 'RTX 5080',
    description: 'test',
    hardware: TranscriptionHardwareInfo(
      operatingSystem: 'windows',
      architecture: 'x86_64',
      gpuName: 'NVIDIA GeForce RTX 5080',
    ),
    config: config,
  );
}
