import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_file_export_service.dart';

class LocalLyricFileExportService implements LyricFileExportService {
  const LocalLyricFileExportService();

  @override
  String encodeLrc(
    LyricDocument document, {
    String? title,
    String? artist,
    String? album,
  }) {
    final buffer = StringBuffer();

    void metadata(String key, String? value) {
      final normalized = value?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      if (normalized == null || normalized.isEmpty) return;
      buffer.writeln('[$key:$normalized]');
    }

    metadata('ti', title);
    metadata('ar', artist);
    metadata('al', album);
    metadata('lang', document.language);
    buffer.writeln('[re:LyricForge]');
    buffer.writeln('[ve:1]');

    // LRC offset direction is interpreted inconsistently across players.
    // Export effective timestamps instead so the same file stays aligned even
    // when a target player ignores or reverses the optional [offset] tag.
    final globalOffset = document.globalOffset ?? Duration.zero;
    final sorted = List<LyricLine>.from(document.lines)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    for (final line in sorted) {
      final text = line.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      if (text.isEmpty) continue;
      final effectiveStart = line.startTime + globalOffset;
      buffer.writeln('[${_timestamp(effectiveStart)}]$text');
    }

    return buffer.toString();
  }

  @override
  Future<String?> exportLrc(
    LyricDocument document, {
    required String suggestedFileName,
    String? title,
    String? artist,
    String? album,
  }) async {
    try {
      final content = encodeLrc(
        document,
        title: title,
        artist: artist,
        album: album,
      );
      return FilePicker.platform.saveFile(
        dialogTitle: '导出同步歌词',
        fileName: _normalizedFileName(suggestedFileName),
        type: FileType.custom,
        allowedExtensions: const ['lrc'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
    } catch (error) {
      throw LyricExportException('导出 LRC 歌词失败', cause: error);
    }
  }

  String _normalizedFileName(String fileName) {
    var normalized = fileName.trim();
    if (normalized.isEmpty) normalized = 'lyrics';
    normalized = normalized
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) normalized = 'lyrics';
    return normalized.toLowerCase().endsWith('.lrc')
        ? normalized
        : '$normalized.lrc';
  }

  String _timestamp(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final minutes = safe.inMinutes.toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds =
        safe.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$milliseconds';
  }
}
