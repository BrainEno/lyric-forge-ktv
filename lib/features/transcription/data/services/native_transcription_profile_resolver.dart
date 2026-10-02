import 'dart:convert';
import 'dart:io';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_profile_resolver.dart';

class NativeTranscriptionProfileResolver
    implements TranscriptionProfileResolver {
  final TranscriptionHardwareInfo? hardwareOverride;

  NativeTranscriptionProfileResolver({
    this.hardwareOverride,
  });

  static const String _qwen17 = 'Qwen/Qwen3-ASR-1.7B';
  static const String _qwen06 = 'Qwen/Qwen3-ASR-0.6B';
  static const String _aligner06 = 'Qwen/Qwen3-ForcedAligner-0.6B';

  @override
  Future<TranscriptionHardwareInfo> detectHardware() async {
    final override = hardwareOverride;
    if (override != null) return override;

    final operatingSystem = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : Platform.isLinux
                ? 'linux'
                : Platform.operatingSystem;

    final architecture = await _detectArchitecture();
    String? cpuName;
    String? gpuName;
    int? gpuMemoryMb;
    int? systemMemoryMb;

    if (Platform.isMacOS) {
      cpuName = await _runText('sysctl', const ['-n', 'machdep.cpu.brand_string']);
      final memoryBytes =
          int.tryParse(await _runText('sysctl', const ['-n', 'hw.memsize']) ?? '');
      if (memoryBytes != null) {
        systemMemoryMb = memoryBytes ~/ (1024 * 1024);
      }
      gpuName = await _detectMacGpu();
    } else if (Platform.isWindows) {
      final gpu = await _detectNvidiaGpu();
      gpuName = gpu.$1;
      gpuMemoryMb = gpu.$2;
      cpuName = Platform.environment['PROCESSOR_IDENTIFIER'];
    }

    return TranscriptionHardwareInfo(
      operatingSystem: operatingSystem,
      architecture: architecture,
      cpuName: cpuName,
      gpuName: gpuName,
      gpuMemoryMb: gpuMemoryMb,
      systemMemoryMb: systemMemoryMb,
    );
  }

  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async {
    final hardware = await detectHardware();
    final selected = config.profilePreference ==
            TranscriptionProfilePreference.automatic
        ? _automaticProfileFor(hardware)
        : config.profilePreference;

    return switch (selected) {
      TranscriptionProfilePreference.rtx5080HighQuality =>
        ResolvedTranscriptionProfile(
          profile: selected,
          label: 'RTX 5080 最高质量',
          description:
              'Qwen3-ASR 1.7B CUDA/BF16 主识别 + ForcedAligner + Whisper large-v3 全曲第二意见',
          hardware: hardware,
          config: config.copyWith(
            engineOrder: TranscriptionEngineOrder.qwenPrimary,
            qwenModelPath: _qwen17,
            qwenAlignerModelPath: _aligner06,
            qwenDevice: 'cuda',
            qwenDtype: 'bf16',
          ),
        ),
      TranscriptionProfilePreference.intelMacHighQuality =>
        ResolvedTranscriptionProfile(
          profile: selected,
          label: 'Intel Mac 高质量',
          description:
              'Whisper large-v3 主识别 + Qwen3-ASR 0.6B CPU 第二意见；Qwen ForcedAligner 提供候选时间信息',
          hardware: hardware,
          config: config.copyWith(
            engineOrder: TranscriptionEngineOrder.whisperPrimary,
            qwenModelPath: _qwen06,
            qwenAlignerModelPath: _aligner06,
            qwenDevice: 'cpu',
            qwenDtype: 'f32',
          ),
        ),
      TranscriptionProfilePreference.custom =>
        ResolvedTranscriptionProfile(
          profile: selected,
          label: '自定义',
          description: '使用当前手动配置的本地识别运行时与模型',
          hardware: hardware,
          config: config,
        ),
      TranscriptionProfilePreference.automatic =>
        throw StateError('automatic profile must resolve before this point'),
    };
  }

  TranscriptionProfilePreference _automaticProfileFor(
    TranscriptionHardwareInfo hardware,
  ) {
    if (hardware.isRtx5080) {
      return TranscriptionProfilePreference.rtx5080HighQuality;
    }
    if (hardware.isIntelMac) {
      return TranscriptionProfilePreference.intelMacHighQuality;
    }
    return TranscriptionProfilePreference.custom;
  }

  Future<String> _detectArchitecture() async {
    if (Platform.isWindows) {
      final value =
          Platform.environment['PROCESSOR_ARCHITECTURE']?.trim().toLowerCase();
      return switch (value) {
        'amd64' => 'x86_64',
        'arm64' => 'arm64',
        null || '' => 'unknown',
        _ => value!,
      };
    }

    return (await _runText('uname', const ['-m']))?.toLowerCase() ?? 'unknown';
  }

  Future<(String?, int?)> _detectNvidiaGpu() async {
    final output = await _runText(
      'nvidia-smi',
      const [
        '--query-gpu=name,memory.total',
        '--format=csv,noheader,nounits',
      ],
    );
    if (output == null || output.trim().isEmpty) return (null, null);

    final line = output.split(RegExp(r'[\r\n]+')).first.trim();
    final parts = line.split(',');
    final name = parts.isEmpty ? null : parts.first.trim();
    final memory = parts.length < 2 ? null : int.tryParse(parts[1].trim());
    return (name, memory);
  }

  Future<String?> _detectMacGpu() async {
    final output = await _runText(
      'system_profiler',
      const ['SPDisplaysDataType', '-json'],
    );
    if (output == null || output.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map) return null;
      final displays = decoded['SPDisplaysDataType'];
      if (displays is! List || displays.isEmpty) return null;

      final names = <String>[];
      for (final item in displays) {
        if (item is! Map) continue;
        final name = item['sppci_model']?.toString().trim();
        if (name != null && name.isNotEmpty) names.add(name);
      }
      return names.isEmpty ? null : names.join(' / ');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _runText(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(executable, arguments);
      if (result.exitCode != 0) return null;
      final text = result.stdout.toString().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }
}
