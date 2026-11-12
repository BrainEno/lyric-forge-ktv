import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_alignment_audio_guard.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/reference_alignment_audio_guard.dart';

void main() {
  late Directory root;
  late File original;
  late File vocal;
  late FileProjectRepository repo;
  late ProjectManifest project;
  late ProjectReferenceAlignmentAudioGuard guard;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reference-alignment-audio-');
    original = File('${root.path}/song.wav');
    vocal = File('${root.path}/vocal.wav');
    await original.writeAsBytes([1, 2, 3]);
    await vocal.writeAsBytes([4, 5, 6]);
    repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'Song');
    project = await repo.updateProject(
      created.copyWith(
        audioAsset: AudioAsset(
          originalPath: original.path,
          vocalPath: vocal.path,
          format: 'wav',
        ),
      ),
    );
    guard = ProjectReferenceAlignmentAudioGuard(projects: repo);
  });
  tearDown(() async => root.delete(recursive: true));
  Future<ReferenceAlignmentAudioCheck> capture({String? path, int? revision}) =>
      guard.capture(
        projectId: project.id,
        projectRevision: revision ?? project.revision,
        audioPath: path ?? vocal.path,
      );

  test(
    'captures and rechecks actual selected audio and project without writes',
    () async {
      final before = (await repo.getProjectById(project.id))!.toJson();
      final result = await capture();
      expect(result.status, ReferenceAlignmentAudioStatus.matches);
      expect(result.snapshot!.audioPath, vocal.path);
      expect(result.snapshot!.audioSha256, hasLength(64));
      expect(
        (await guard.verify(result.snapshot!)).status,
        ReferenceAlignmentAudioStatus.matches,
      );
      expect((await repo.getProjectById(project.id))!.toJson(), before);
    },
  );

  test('changed bytes even at same size are not matches', () async {
    final snapshot = (await capture()).snapshot!;
    await vocal.writeAsBytes([4, 5, 7]);
    expect(
      (await guard.verify(snapshot)).status,
      ReferenceAlignmentAudioStatus.audioChanged,
    );
  });

  test('a stale or missing project is rejected', () async {
    expect(
      (await capture(revision: project.revision - 1)).status,
      ReferenceAlignmentAudioStatus.projectChanged,
    );
    final snapshot = (await capture()).snapshot!;
    await repo.updateProject(project.copyWith(name: 'updated'));
    expect(
      (await guard.verify(snapshot)).status,
      ReferenceAlignmentAudioStatus.projectChanged,
    );
    await repo.deleteProject(project.id);
    expect(
      (await guard.verify(snapshot)).status,
      ReferenceAlignmentAudioStatus.projectChanged,
    );
  });

  test('different path is rejected even if bytes match', () async {
    await original.writeAsBytes([4, 5, 6]);
    final result = await capture(path: original.path);
    expect(result.status, ReferenceAlignmentAudioStatus.audioSelectionChanged);
    expect(result.snapshot, isNull);
  });

  test(
    'original path is used when vocal is absent, not normalized audio',
    () async {
      project = await repo.updateProject(
        project.copyWith(
          audioAsset: AudioAsset(
            originalPath: original.path,
            normalizedPath: vocal.path,
            format: 'wav',
          ),
        ),
      );
      expect(
        (await capture(path: original.path)).status,
        ReferenceAlignmentAudioStatus.matches,
      );
      expect(
        (await capture(path: vocal.path)).status,
        ReferenceAlignmentAudioStatus.audioSelectionChanged,
      );
    },
  );

  test('missing and unreadable files are unavailable', () async {
    await vocal.delete();
    expect(
      (await capture()).status,
      ReferenceAlignmentAudioStatus.audioUnavailable,
    );
    guard = ProjectReferenceAlignmentAudioGuard(
      projects: repo,
      hashAudio: (_) async => throw const FileSystemException('unreadable'),
    );
    expect(
      (await capture()).status,
      ReferenceAlignmentAudioStatus.audioUnavailable,
    );
  });

  test('concurrent modification during hashing is rejected', () async {
    guard = ProjectReferenceAlignmentAudioGuard(
      projects: repo,
      hashAudio: (_) async => throw const AsrAudioChangedDuringHashException(),
    );
    expect(
      (await capture()).status,
      ReferenceAlignmentAudioStatus.audioChanged,
    );
  });

  test(
    'project revision changes during hashing invalidate the snapshot',
    () async {
      guard = ProjectReferenceAlignmentAudioGuard(
        projects: repo,
        hashAudio: (_) async {
          await repo.updateProject(project.copyWith(name: 'changed'));
          return 'digest';
        },
      );
      final result = await capture();
      expect(result.status, ReferenceAlignmentAudioStatus.projectChanged);
      expect(result.snapshot, isNull);
    },
  );

  test('project change during verification is also rejected', () async {
    final snapshot = (await capture()).snapshot!;
    guard = ProjectReferenceAlignmentAudioGuard(
      projects: repo,
      hashAudio: (_) async {
        await repo.updateProject(project.copyWith(name: 'later'));
        return snapshot.audioSha256;
      },
    );
    expect(
      (await guard.verify(snapshot)).status,
      ReferenceAlignmentAudioStatus.projectChanged,
    );
  });

  test('unexpected errors are not misreported as a match', () async {
    guard = ProjectReferenceAlignmentAudioGuard(
      projects: repo,
      hashAudio: (_) async => throw StateError('bug'),
    );
    await expectLater(capture(), throwsStateError);
  });
}
