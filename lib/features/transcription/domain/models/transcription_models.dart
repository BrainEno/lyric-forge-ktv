import '../../../project/domain/models/lyric_document.dart';

enum TranscriptionStage {
  validating,
  preprocessing,
  loadingModel,
  transcribing,
  aligning,
  fallback,
  parsing,
  completed,
  cancelled,
  failed,
}

enum TranscriptionMode {
  highestQuality,
  whisperOnly,
}

enum TranscriptionProfilePreference {
  automatic,
  rtx5080HighQuality,
  intelMacHighQuality,
  custom,
}

enum TranscriptionEngineOrder {
  qwenPrimary,
  whisperPrimary,
}

class TranscriptionHardwareInfo {
  final String operatingSystem;
  final String architecture;
  final String? cpuName;
  final String? gpuName;
  final int? gpuMemoryMb;
  final int? systemMemoryMb;

  const TranscriptionHardwareInfo({
    required this.operatingSystem,
    required this.architecture,
    this.cpuName,
    this.gpuName,
    this.gpuMemoryMb,
    this.systemMemoryMb,
  });

  bool get isIntelMac =>
      operatingSystem == 'macos' &&
      (architecture == 'x86_64' || architecture == 'amd64');

  bool get isWindowsNvidia =>
      operatingSystem == 'windows' &&
      (gpuName?.toLowerCase().contains('nvidia') == true ||
          gpuName?.toLowerCase().contains('geforce') == true);

  bool get isRtx5080 =>
      isWindowsNvidia && gpuName?.toLowerCase().contains('rtx 5080') == true;
}

class ResolvedTranscriptionProfile {
  final TranscriptionProfilePreference profile;
  final String label;
  final String description;
  final TranscriptionHardwareInfo hardware;
  final TranscriptionConfig config;

  const ResolvedTranscriptionProfile({
    required this.profile,
    required this.label,
    required this.description,
    required this.hardware,
    required this.config,
  });
}

class TranscriptionConfig {
  final TranscriptionMode mode;
  final TranscriptionProfilePreference profilePreference;
  final TranscriptionEngineOrder engineOrder;

  // Qwen3-ASR native runtime
  final String qwenExecutable;
  final String qwenModelPath;
  final String qwenAlignerModelPath;
  final String qwenDevice;
  final String qwenDtype;

  // Whisper runtime
  final String whisperExecutable;
  final String modelPath;

  // Shared processing
  final String ffmpegExecutable;
  final String language;

  // Highest-quality review policy
  final int fallbackConfidenceThreshold;
  final int maxFallbackSegments;

  const TranscriptionConfig({
    this.mode = TranscriptionMode.highestQuality,
    this.profilePreference = TranscriptionProfilePreference.automatic,
    this.engineOrder = TranscriptionEngineOrder.qwenPrimary,
    this.qwenExecutable = '',
    this.qwenModelPath = 'Qwen/Qwen3-ASR-1.7B',
    this.qwenAlignerModelPath = 'Qwen/Qwen3-ForcedAligner-0.6B',
    this.qwenDevice = 'cuda',
    this.qwenDtype = 'bf16',
    required this.whisperExecutable,
    required this.modelPath,
    this.ffmpegExecutable = 'ffmpeg',
    this.language = 'auto',
    this.fallbackConfidenceThreshold = 70,
    this.maxFallbackSegments = 20,
  });

  bool get isWhisperConfigured =>
      whisperExecutable.trim().isNotEmpty && modelPath.trim().isNotEmpty;

  bool get isQwenConfigured =>
      qwenExecutable.trim().isNotEmpty &&
      qwenModelPath.trim().isNotEmpty &&
      qwenAlignerModelPath.trim().isNotEmpty;

  bool get isHighQualityConfigured =>
      isQwenConfigured && isWhisperConfigured;

  bool get isConfigured {
    return switch (mode) {
      TranscriptionMode.highestQuality => isHighQualityConfigured,
      TranscriptionMode.whisperOnly => isWhisperConfigured,
    };
  }

  TranscriptionConfig copyWith({
    TranscriptionMode? mode,
    TranscriptionProfilePreference? profilePreference,
    TranscriptionEngineOrder? engineOrder,
    String? qwenExecutable,
    String? qwenModelPath,
    String? qwenAlignerModelPath,
    String? qwenDevice,
    String? qwenDtype,
    String? whisperExecutable,
    String? modelPath,
    String? ffmpegExecutable,
    String? language,
    int? fallbackConfidenceThreshold,
    int? maxFallbackSegments,
  }) {
    return TranscriptionConfig(
      mode: mode ?? this.mode,
      profilePreference: profilePreference ?? this.profilePreference,
      engineOrder: engineOrder ?? this.engineOrder,
      qwenExecutable: qwenExecutable ?? this.qwenExecutable,
      qwenModelPath: qwenModelPath ?? this.qwenModelPath,
      qwenAlignerModelPath:
          qwenAlignerModelPath ?? this.qwenAlignerModelPath,
      qwenDevice: qwenDevice ?? this.qwenDevice,
      qwenDtype: qwenDtype ?? this.qwenDtype,
      whisperExecutable: whisperExecutable ?? this.whisperExecutable,
      modelPath: modelPath ?? this.modelPath,
      ffmpegExecutable: ffmpegExecutable ?? this.ffmpegExecutable,
      language: language ?? this.language,
      fallbackConfidenceThreshold:
          fallbackConfidenceThreshold ?? this.fallbackConfidenceThreshold,
      maxFallbackSegments:
          maxFallbackSegments ?? this.maxFallbackSegments,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'profilePreference': profilePreference.name,
      'engineOrder': engineOrder.name,
      'qwenExecutable': qwenExecutable,
      'qwenModelPath': qwenModelPath,
      'qwenAlignerModelPath': qwenAlignerModelPath,
      'qwenDevice': qwenDevice,
      'qwenDtype': qwenDtype,
      'whisperExecutable': whisperExecutable,
      'modelPath': modelPath,
      'ffmpegExecutable': ffmpegExecutable,
      'language': language,
      'fallbackConfidenceThreshold': fallbackConfidenceThreshold,
      'maxFallbackSegments': maxFallbackSegments,
    };
  }

  factory TranscriptionConfig.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    final mode = modeName == null
        ? TranscriptionMode.whisperOnly
        : TranscriptionMode.values.asNameMap()[modeName] ??
            TranscriptionMode.whisperOnly;

    final profileName = json['profilePreference'] as String?;
    final profilePreference = profileName == null
        ? mode == TranscriptionMode.highestQuality
            ? TranscriptionProfilePreference.automatic
            : TranscriptionProfilePreference.custom
        : TranscriptionProfilePreference.values.asNameMap()[profileName] ??
            TranscriptionProfilePreference.custom;

    final orderName = json['engineOrder'] as String?;
    final engineOrder = orderName == null
        ? TranscriptionEngineOrder.qwenPrimary
        : TranscriptionEngineOrder.values.asNameMap()[orderName] ??
            TranscriptionEngineOrder.qwenPrimary;

    return TranscriptionConfig(
      mode: mode,
      profilePreference: profilePreference,
      engineOrder: engineOrder,
      qwenExecutable: json['qwenExecutable'] as String? ?? '',
      qwenModelPath:
          json['qwenModelPath'] as String? ?? 'Qwen/Qwen3-ASR-1.7B',
      qwenAlignerModelPath:
          json['qwenAlignerModelPath'] as String? ??
              'Qwen/Qwen3-ForcedAligner-0.6B',
      qwenDevice: json['qwenDevice'] as String? ?? 'cuda',
      qwenDtype: json['qwenDtype'] as String? ?? 'bf16',
      whisperExecutable: json['whisperExecutable'] as String? ?? '',
      modelPath: json['modelPath'] as String? ?? '',
      ffmpegExecutable: json['ffmpegExecutable'] as String? ?? 'ffmpeg',
      language: json['language'] as String? ?? 'auto',
      fallbackConfidenceThreshold:
          (json['fallbackConfidenceThreshold'] as num?)?.toInt() ?? 70,
      maxFallbackSegments:
          (json['maxFallbackSegments'] as num?)?.toInt() ?? 20,
    );
  }
}

class TranscriptionRequest {
  final String inputAudioPath;
  final String outputDirectory;
  final TranscriptionConfig config;
  final String context;

  const TranscriptionRequest({
    required this.inputAudioPath,
    required this.outputDirectory,
    required this.config,
    this.context = '',
  });
}

class TranscriptionProgress {
  final TranscriptionStage stage;
  final double progress;
  final String message;

  const TranscriptionProgress({
    required this.stage,
    required this.progress,
    required this.message,
  });
}

class TranscriptionResult {
  final LyricDocument lyrics;
  final String normalizedAudioPath;
  final String rawJsonPath;
  final String detectedLanguage;

  const TranscriptionResult({
    required this.lyrics,
    required this.normalizedAudioPath,
    required this.rawJsonPath,
    required this.detectedLanguage,
  });
}

class TranscriptionException implements Exception {
  final String message;
  final String? details;

  const TranscriptionException(this.message, {this.details});

  @override
  String toString() {
    if (details == null || details!.trim().isEmpty) return message;
    return message + ': ' + details!;
  }
}
