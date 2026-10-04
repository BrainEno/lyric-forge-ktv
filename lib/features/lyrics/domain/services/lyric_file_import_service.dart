import '../../../project/domain/models/lyric_document.dart';

enum LyricImportFormat {
  lrc,
  srt,
  webvtt,
  ass,
  plainText,
}

class LyricImportResult {
  final LyricDocument document;
  final LyricImportFormat format;
  final String sourcePath;
  final String detectedEncoding;
  final String? title;
  final String? artist;
  final String? album;

  const LyricImportResult({
    required this.document,
    required this.format,
    required this.sourcePath,
    required this.detectedEncoding,
    this.title,
    this.artist,
    this.album,
  });
}

class LyricImportException implements Exception {
  final String message;
  final Object? cause;

  const LyricImportException(this.message, {this.cause});

  @override
  String toString() => cause == null
      ? 'LyricImportException: $message'
      : 'LyricImportException: $message ($cause)';
}

abstract class LyricFileImportService {
  Set<String> get supportedExtensions;

  Future<LyricImportResult> importFile(
    String path, {
    String? encodingHint,
  });

  LyricImportResult parseText(
    String text, {
    required String extension,
    String sourcePath = '',
    String detectedEncoding = 'unicode',
  });
}
