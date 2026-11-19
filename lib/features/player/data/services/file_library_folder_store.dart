import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/services/library_folder_settings.dart';

/// Keeps the chosen library folder in `library_folder.json` beside the
/// app's other settings.
class FileLibraryFolderStore implements LibraryFolderStore {
  const FileLibraryFolderStore({this.rootDirectory});

  static const String fileName = 'library_folder.json';
  static const String _folderKey = 'folder';

  /// Overrides the app support folder in tests.
  final Directory? rootDirectory;

  Future<File> _file() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + fileName);
  }

  @override
  Future<String?> loadFolder() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded[_folderKey];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on Exception {
      // A damaged settings file falls back to the default folder.
      return null;
    }
  }

  @override
  Future<void> saveFolder(String? path) async {
    final file = await _file();
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(
      jsonEncode(<String, Object>{'version': 1, _folderKey: trimmed}),
      flush: true,
    );
  }
}

/// Lists lyric files with `dart:io`; see [LyricFileLister].
///
/// Hidden folders (`.git`, `.Trash`) are skipped, unreadable folders are
/// skipped instead of failing the whole pass, and links are not followed so
/// a link loop cannot hang the scan.
Future<List<String>> listLyricFiles(
  String directory, {
  required bool recursive,
  required Set<String> extensions,
}) async {
  final root = Directory(directory);
  final found = <String>[];
  try {
    if (!await root.exists()) return found;
    await for (final entity in root.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = entity.path.substring(root.path.length);
      if (_inHiddenFolder(relative)) continue;
      final name = relative.split(RegExp(r'[\\/]')).last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      if (extensions.contains(name.substring(dot + 1).toLowerCase())) {
        found.add(entity.path);
      }
    }
  } on FileSystemException {
    // Keep what was listed before the unreadable folder.
  }
  found.sort();
  return found;
}

bool _inHiddenFolder(String relativePath) {
  final parts = relativePath.split(RegExp(r'[\\/]'));
  for (var index = 0; index < parts.length - 1; index++) {
    if (parts[index].startsWith('.')) return true;
  }
  return false;
}
