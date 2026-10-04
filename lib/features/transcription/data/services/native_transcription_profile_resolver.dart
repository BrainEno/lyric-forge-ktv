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
      final gpu = await _detectMacGpu();
      gpuName = gpu.$1;
      gpuMemoryMb = gpu.$2;
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

    var qwenModelPath = config.qwenModelPath;
    var qwenAlignerModelPath = config.qwenAlignerModelPath;
    if (selected == TranscriptionProfilePreference.rtx5080HighQuality) {
      qwenModelPath = await _preferMatchingLocalModel(
        config.qwenModelPath,
        _qwen17,
      );
      qwenAlignerModelPath = await _preferMatchingLocalModel(
        config.qwenAlignerModelPath,
        _aligner06,
      );
    } else if (selected ==
        TranscriptionProfilePreference.intelMacHighQuality) {
      qwenModelPath = await _preferMatchingLocalModel(
        config.qwenModelPath,
        _qwen06,
      );
      qwenAlignerModelPath = await _preferMatchingLocalModel(
        config.qwenAlignerModelPath,
        _aligner06,
      );
    }

    return switch (selected) {
      TranscriptionProfilePreference.rtx5080HighQuality =>
        ResolvedTranscriptionProfile(
          profile: selected,
          label: 'RTX 5080 最高质量',
          description:
              'Qwen3-ASR 1.7B CUDA/BF16 主识别 + ForcedAligner + Whisper large-v3 全曲第二意见',
          hardware: hardware,
          config: config.copyWith(
            profilePreference: selected,
            engineOrder: TranscriptionEngineOrder.qwenPrimary,
            qwenModelPath: qwenModelPath,
            qwenAlignerModelPath: qwenAlignerModelPath,
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
            profilePreference: selected,
            engineOrder: TranscriptionEngineOrder.whisperPrimary,
            qwenModelPath: qwenModelPath,
            qwenAlignerModelPath: qwenAlignerModelPath,
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

  Future<String> _preferMatchingLocalModel(
    String configured,
    String expectedModelId,
  ) async {
    final value = configured.trim();
    if (value.isEmpty) return expectedModelId;

    final expectedName = expectedModelId.split('/').last.toLowerCase();
    if (!value.toLowerCase().contains(expectedName)) {
      return expectedModelId;
    }

    try {
      final type = await FileSystemEntity.type(value, followLinks: true);
      return type == FileSystemEntityType.directory ? value : expectedModelId;
    } catch (_) {
      return expectedModelId;
    }
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
      if (value == null || value.isEmpty) return 'unknown';
      if (value == 'amd64') return 'x86_64';
      return value;
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

  Future<(String?, int?)> _detectMacGpu() async {
    final output = await _runText(
      'system_profiler',
      const ['-json', 'SPDisplaysDataType'],
    );
    if (output == null || output.trim().isEmpty) return (null, null);

    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map) return (null, null);
      final displays = decoded['SPDisplaysDataType'];
      if (displays is! List || displays.isEmpty) return (null, null);

      final names = <String>[];
      var maxMemoryMb = 0;

      for (final item in displays) {
        if (item is! Map) continue;

        final name = item['sppci_model']?.toString().trim();
        if (name != null && name.isNotEmpty) names.add(name);

        final memoryText = (item['spdisplays_vram'] ??
                item['spdisplays_vram_shared'] ??
                item['spdisplays_vram_dynamic'])
            ?.toString();
        final memoryMb = _parseMemoryMb(memoryText);
        if (memoryMb != null && memoryMb > maxMemoryMb) {
          maxMemoryMb = memoryMb;
        }
      }

      return (
        names.isEmpty ? null : names.join(' / '),
        maxMemoryMb == 0 ? null : maxMemoryMb,
      );
    } catch (_) {
      return (null, null);
    }
  }

  int? _parseMemoryMb(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'(\d+(?:\.\d+)?)\s*(GB|MB)', caseSensitive: false)
            .firstMatch(value);
    if (match == null) return null;

    final amount = double.tryParse(match.group(1) ?? '');
    if (amount == null) return null;
    final unit = (match.group(2) ?? '').toUpperCase();
    return unit == 'GB' ? (amount * 1024).round() : amount.round();
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
