import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../project/domain/models/project_manifest.dart';

class KtvProjectStorage {
  const KtvProjectStorage._();

  static Future<Directory> resolveProjectDirectory(
    ProjectManifest project, {
    Directory? applicationSupportDirectory,
  }) async {
    final explicit = project.projectDirectory?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return Directory(explicit);
    }
    final support =
        applicationSupportDirectory ?? await getApplicationSupportDirectory();
    return Directory(
      join(join(join(support.path, 'LyricForge'), 'Projects'), project.id),
    );
  }

  static String join(String left, String right) =>
      left.endsWith(Platform.pathSeparator)
          ? '$left$right'
          : '$left${Platform.pathSeparator}$right';
}
