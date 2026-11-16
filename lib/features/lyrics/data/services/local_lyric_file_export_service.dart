import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_export_encoder.dart';
import '../../domain/services/lyric_file_export_service.dart';

class LocalLyricFileExportService implements LyricFileExportService {
  const LocalLyricFileExportService({
    this.encoder = const LyricExportEncoder(),
  });

  final LyricExportEncoder encoder;

  @override
  String encodeLrc(
    LyricDocument document, {
    String? title,
    String? artist,
    String? album,
  }) {
    // LRC offset direction is interpreted inconsistently across players.
    // The encoder writes effective timestamps instead so the same file stays
    // aligned even when a target player ignores or reverses [offset].
    return encoder.encodeLrc(
      document,
      metadata: LyricExportMetadata(title: title, artist: artist, album: album),
    );
  }

  @override
  Future<String?> exportLrc(
    LyricDocument document, {
    required String suggestedFileName,
    String? title,
    String? artist,
    String? album,
  }) {
    return exportFile(
      document,
      format: LyricExportFormat.lrc,
      suggestedFileName: suggestedFileName,
      metadata: LyricExportMetadata(title: title, artist: artist, album: album),
    );
  }

  @override
  Future<String?> exportFile(
    LyricDocument document, {
    required LyricExportFormat format,
    required String suggestedFileName,
    LyricExportOptions options = const LyricExportOptions(),
    LyricExportMetadata metadata = const LyricExportMetadata(),
  }) async {
    try {
      final content = encoder.encode(
        document,
        format,
        options: options,
        metadata: metadata,
      );
      return await FilePicker.platform.saveFile(
        dialogTitle: '导出${format.label}',
        fileName: normalizedFileName(suggestedFileName, format.extension),
        type: FileType.custom,
        allowedExtensions: [format.extension],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
    } catch (error) {
      throw LyricExportException('导出${format.label}失败', cause: error);
    }
  }

  /// A file name safe on every desktop file system, ending in [extension].
  static String normalizedFileName(String fileName, String extension) {
    var normalized = fileName.trim();
    if (normalized.isEmpty) normalized = 'lyrics';
    normalized = normalized
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) normalized = 'lyrics';
    return normalized.toLowerCase().endsWith('.$extension')
        ? normalized
        : '$normalized.$extension';
  }
}
