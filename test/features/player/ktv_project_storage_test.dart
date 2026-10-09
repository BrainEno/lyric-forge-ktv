import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/ktv_project_storage.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  ProjectManifest project({String? directory}) => ProjectManifest(
        id: 'song-42',
        name: 'Song',
        createdAt: DateTime(2026, 10, 9),
        updatedAt: DateTime(2026, 10, 9),
        projectDirectory: directory,
      );

  test('explicit project directory always wins', () async {
    final explicit = Directory.systemTemp.absolute.path;
    final support = await Directory.systemTemp.createTemp('ktv-support-');
    try {
      final resolved = await KtvProjectStorage.resolveProjectDirectory(
        project(directory: explicit),
        applicationSupportDirectory: support,
      );
      expect(resolved.path, explicit);
    } finally {
      await support.delete(recursive: true);
    }
  });

  test('null project directory resolves to app-managed project storage', () async {
    final support = await Directory.systemTemp.createTemp('ktv-support-');
    try {
      final resolved = await KtvProjectStorage.resolveProjectDirectory(
        project(),
        applicationSupportDirectory: support,
      );
      expect(
        resolved.path,
        [support.path, 'LyricForge', 'Projects', 'song-42']
            .join(Platform.pathSeparator),
      );
    } finally {
      await support.delete(recursive: true);
    }
  });
}
