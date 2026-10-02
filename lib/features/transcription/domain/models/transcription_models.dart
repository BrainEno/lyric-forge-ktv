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

class TranscriptionConfig {
  final TranscriptionMode mode;

  // Qwen3-ASR native runtime
  final String qwenExecutable;
  final String qwenModelPath;
  final String qwenAlignerModelPath;
  final String qwenDevice;
  final String qwenDtype;

  // Whisper fallback / compatibility runtime
  final String whisperExecutable;
  final String modelPath;

  // Shared processing
  final String ffmpegExecutable;
  final String language;

  // Highest-quality fallback policy
  final int fallbackConfidenceThreshold;
  final int maxFallbackSegments;

  const TranscriptionConfig({
    this.mode = TranscriptionMode.highestQuality,
    this.qwenExecutable = '',
    this.qwenModelPath = '',
    this.qwenAlignerModelPath = '',
    this.qwenDevice = 'cuda',
    this.qwenDtype = 'bf16',
    required this.whisperExecutable,
    required this.modelPath,
    this.ffmpegExecutable = 'ffmpeg',
    this.language = 'auto',
    this.fallbackConfidenceThreshold = 70,
    this.maxFallbackSegments = 12,
  });

  bool get isWhisperConfigured =>
      whisperExecutable.trim().isNotEmpty && modelPath.trim().isNotEmpty;

  bool get isQwenConfigured =>
      qwenExecutable.trim().isNotEmpty &&
      qwenModelPath.trim().isNotEmpty &&
      qwenAlignerModelPath.trim().isNotEmpty;

  bool get isConfigured {
    return switch (mode) {
      TranscriptionMode.highestQuality =>
        isQwenConfigured && isWhisperConfigured,
      TranscriptionMode.whisperOnly => isWhisperConfigured,
    };
  }

  TranscriptionConfig copyWith({
    TranscriptionMode? mode,
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
        // Existing settings from the Whisper-only implementation remain valid.
        ? TranscriptionMode.whisperOnly
        : TranscriptionMode.values.asNameMap()[modeName] ??
            TranscriptionMode.whisperOnly;

    return TranscriptionConfig(
      mode: mode,
      qwenExecutable: json['qwenExecutable'] as String? ?? '',
      qwenModelPath: json['qwenModelPath'] as String? ?? '',
      qwenAlignerModelPath:
          json['qwenAlignerModelPath'] as String? ?? '',
      qwenDevice: json['qwenDevice'] as String? ?? 'cuda',
      qwenDtype: json['qwenDtype'] as String? ?? 'bf16',
      whisperExecutable: json['whisperExecutable'] as String? ?? '',
      modelPath: json['modelPath'] as String? ?? '',
      ffmpegExecutable: json['ffmpegExecutable'] as String? ?? 'ffmpeg',
      language: json['language'] as String? ?? 'auto',
      fallbackConfidenceThreshold:
          (json['fallbackConfidenceThreshold'] as num?)?.toInt() ?? 70,
      maxFallbackSegments:
          (json['maxFallbackSegments'] as num?)?.toInt() ?? 12,
    );
  }
}

class TranscriptionRequest {
  final String inputAudioPath;
  final String outputDirectory;
  final TranscriptionConfig config;

  const TranscriptionRequest({
    required this.inputAudioPath,
    required this.outputDirectory,
    required this.config,
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
