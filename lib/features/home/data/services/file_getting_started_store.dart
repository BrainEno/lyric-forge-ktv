import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/getting_started.dart';
import '../../domain/services/getting_started_store.dart';

/// Saves the 开始使用 checklist state (D-070) as a small JSON file in the
/// application support directory, next to the other preference files.
class FileGettingStartedStore implements GettingStartedStore {
  static const String fileName = 'getting_started.json';
  static const String visibilityKey = 'visibility';
  static const String openedKtvKey = 'openedKtv';

  /// Where the file lives; the application support directory when null.
  final Directory? rootDirectory;

  const FileGettingStartedStore({this.rootDirectory});

  Future<File> _file() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + fileName);
  }

  /// Null when there is no file or it is not the JSON this store writes.
  @override
  Future<GettingStartedPreferences?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return GettingStartedPreferences(
        visibility: GettingStartedVisibility.fromId(decoded[visibilityKey]),
        openedKtv: decoded[openedKtvKey] == true,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(GettingStartedPreferences preferences) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(<String, Object>{
        'version': 1,
        visibilityKey: preferences.visibility.name,
        openedKtvKey: preferences.openedKtv,
      }),
      flush: true,
    );
  }
}
