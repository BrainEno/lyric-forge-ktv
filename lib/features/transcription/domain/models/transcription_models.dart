import '../../../project/domain/models/lyric_document.dart';

enum TranscriptionStage {
  validating,
  preprocessing,
  transcribing,
  parsing,
  completed,
  cancelled,
  failed,
}

class TranscriptionConfig {
  final String whisperExecutable;
  final String modelPath;
  final String ffmpegExecutable;
  final String language;

  const TranscriptionConfig({
    required this.whisperExecutable,
    required this.modelPath,
    this.ffmpegExecutable = 'ffmpeg',
    this.language = 'auto',
  });

  bool get isConfigured =>
      whisperExecutable.trim().isNotEmpty && modelPath.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'whisperExecutable': whisperExecutable,
      'modelPath': modelPath,
      'ffmpegExecutable': ffmpegExecutable,
      'language': language,
    };
  }

  factory TranscriptionConfig.fromJson(Map<String, dynamic> json) {
    return TranscriptionConfig(
      whisperExecutable: json['whisperExecutable'] as String? ?? '',
      modelPath: json['modelPath'] as String? ?? '',
      ffmpegExecutable: json['ffmpegExecutable'] as String? ?? 'ffmpeg',
      language: json['language'] as String? ?? 'auto',
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
