import '../../../project/domain/models/lyric_document.dart';

abstract class LyricFileExportService {
  String encodeLrc(
    LyricDocument document, {
    String? title,
    String? artist,
    String? album,
  });

  Future<String?> exportLrc(
    LyricDocument document, {
    required String suggestedFileName,
    String? title,
    String? artist,
    String? album,
  });
}

class LyricExportException implements Exception {
  final String message;
  final Object? cause;

  const LyricExportException(this.message, {this.cause});

  @override
  String toString() => cause == null ? message : '$message\n$cause';
}
