import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../lyrics/domain/services/lyric_file_import_service.dart';

/// Picks one lyric file (LRC, TXT, SRT …) for [importer]; null when the user
/// cancels.
///
/// On a phone the picker is not filtered (D-058): iOS turns extensions such
/// as `lrc` into made-up file types and may grey out the very lyric files the
/// user copied over from the computer. The extension is checked afterwards
/// instead, by [isSupportedLyricFile].
Future<String?> pickLyricFilePath(
  LyricFileImportService importer, {
  String dialogTitle = '导入歌词文件',
}) async {
  final phone = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  final picked = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    type: phone ? FileType.any : FileType.custom,
    allowedExtensions: phone
        ? null
        : (importer.supportedExtensions.toList()..sort()),
    allowMultiple: false,
  );
  final path = picked?.files.single.path;
  if (path == null || path.isEmpty) return null;
  if (!isSupportedLyricFile(path, importer.supportedExtensions)) {
    throw LyricImportException(unsupportedLyricFileMessage(importer));
  }
  return path;
}

/// Whether [path] ends in one of [extensions], ignoring case.
bool isSupportedLyricFile(String path, Iterable<String> extensions) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return false;
  final extension = name.substring(dot + 1).toLowerCase();
  return extensions.any((candidate) => candidate.toLowerCase() == extension);
}

/// The note for a file that is not a lyric file.
String unsupportedLyricFileMessage(LyricFileImportService importer) {
  final names = importer.supportedExtensions.map((e) => e.toUpperCase());
  return '请选择歌词文件（${names.join(' / ')}）';
}
