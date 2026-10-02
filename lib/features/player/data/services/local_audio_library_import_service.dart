import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../domain/services/audio_library_import_service.dart';

class LocalAudioLibraryImportService implements AudioLibraryImportService {
  static const _supported = <String>[
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
  ];

  @override
  List<String> get supportedExtensions => _supported;

  @override
  Future<List<String>> pickAudioFiles() async {
    final useUnfilteredMacPicker = Platform.isMacOS;
    final result = await FilePicker.platform.pickFiles(
      type: useUnfilteredMacPicker ? FileType.any : FileType.custom,
      allowedExtensions: useUnfilteredMacPicker ? null : _supported,
      allowMultiple: true,
      dialogTitle: '选择一个或多个音频文件',
      allowCompression: false,
      withData: false,
      withReadStream: false,
    );

    if (result == null) return const [];

    final seen = <String>{};
    final paths = <String>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null || !_isSupported(path) || !seen.add(path)) continue;
      paths.add(path);
    }
    return paths;
  }

  @override
  Future<List<String>> pickAudioDirectory() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择音乐文件夹',
      lockParentWindow: true,
    );
    if (directoryPath == null) return const [];

    final directory = Directory(directoryPath);
    if (!await directory.exists()) return const [];

    final paths = <String>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && _isSupported(entity.path)) {
        paths.add(entity.path);
      }
    }

    paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return paths;
  }

  bool _isSupported(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return _supported.contains(path.substring(dot + 1).toLowerCase());
  }
}
