import '../../../project/domain/models/lyric_document.dart';
import 'lyric_export_encoder.dart';

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

  /// Encodes [document] as [format] and asks the user where to save it.
  ///
  /// Returns the saved path, or null when the user cancelled. Throws
  /// [LyricExportException] when writing fails.
  Future<String?> exportFile(
    LyricDocument document, {
    required LyricExportFormat format,
    required String suggestedFileName,
    LyricExportOptions options = const LyricExportOptions(),
    LyricExportMetadata metadata = const LyricExportMetadata(),
  });
}

class LyricExportException implements Exception {
  final String message;
  final Object? cause;

  const LyricExportException(this.message, {this.cause});

  @override
  String toString() => cause == null ? message : '$message\n$cause';
}
