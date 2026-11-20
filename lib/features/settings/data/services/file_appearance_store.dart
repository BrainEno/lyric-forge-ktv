import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_appearance.dart';
import '../../../../core/theme/app_palette.dart';

/// Saves the chosen theme (decision D-042) as a small JSON file in the
/// application support directory, next to the other preference files.
class FileAppearanceStore implements AppearanceStore {
  static const String fileName = 'appearance_preferences.json';
  static const String themeKey = 'theme';

  /// Where the file lives; the application support directory when null.
  final Directory? rootDirectory;

  const FileAppearanceStore({this.rootDirectory});

  Future<File> _file() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + fileName);
  }

  /// The saved theme; null when there is no file, the file is not the JSON
  /// this store writes, or it names a theme this version does not have.
  @override
  Future<AppThemeVariant?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return AppThemeVariant.fromId(decoded[themeKey]);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(AppThemeVariant variant) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(<String, Object>{'version': 1, themeKey: variant.id}),
      flush: true,
    );
  }
}
