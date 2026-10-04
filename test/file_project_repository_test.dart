import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  test('projects survive repository recreation', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-projects-');
    addTearDown(() => root.delete(recursive: true));

    final first = FileProjectRepository(rootDirectory: root);
    var project = await first.createProject(name: 'Persistent Song');
    project = await first.updateProject(
      project.copyWith(
        currentStage: ProcessingStage.audioImported,
        audioAsset: const AudioAsset(
          originalPath: '/music/song.flac',
          format: 'flac',
        ),
      ),
    );

    final restoredRepository = FileProjectRepository(rootDirectory: root);
    final restored = await restoredRepository.getProjectById(project.id);

    expect(restored, isNotNull);
    expect(restored!.name, 'Persistent Song');
    expect(restored.currentStage, ProcessingStage.audioImported);
    expect(restored.audioAsset?.originalPath, '/music/song.flac');
  });
}
