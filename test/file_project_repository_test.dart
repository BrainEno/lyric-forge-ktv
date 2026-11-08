import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

void main() {
  test('conditional project updates reject stale editor snapshots', () async {
    final root = await Directory.systemTemp.createTemp(
      'lyricforge-project-conflict-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final repository = FileProjectRepository(rootDirectory: root);
    final openedSnapshot = await repository.createProject(name: 'Song');
    final backgroundUpdate = await repository.updateProject(
      openedSnapshot.copyWith(
        lyricDocument: _lyricDocument(text: '后台识别结果'),
        currentStage: ProcessingStage.transcriptionComplete,
        metadata: const {
          'transcription': {'engine': 'qwen'},
        },
      ),
    );

    await expectLater(
      repository.updateProjectIfUnchanged(
        openedSnapshot.copyWith(
          lyricDocument: _lyricDocument(text: '编辑器旧快照'),
          status: ProjectStatus.editing,
        ),
        expectedRevision: openedSnapshot.revision,
      ),
      throwsA(
        isA<ProjectUpdateConflictException>().having(
          (error) => error.currentProject?.revision,
          'current revision',
          backgroundUpdate.revision,
        ),
      ),
    );

    final persisted = await repository.getProjectById(openedSnapshot.id);
    expect(persisted?.revision, backgroundUpdate.revision);
    expect(persisted?.lyricDocument?.lines.single.text, '后台识别结果');
    expect(persisted?.metadata['transcription'], {'engine': 'qwen'});
  });

  test('only one concurrent writer can claim a project revision', () async {
    final root = await Directory.systemTemp.createTemp(
      'lyricforge-project-race-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final repository = FileProjectRepository(rootDirectory: root);
    final snapshot = await repository.createProject(name: 'Song');

    Future<bool> save(String name) async {
      try {
        await repository.updateProjectIfUnchanged(
          snapshot.copyWith(name: name),
          expectedRevision: snapshot.revision,
        );
        return true;
      } on ProjectUpdateConflictException {
        return false;
      }
    }

    final outcomes = await Future.wait([
      save('First editor'),
      save('Second editor'),
    ]);
    expect(outcomes.where((saved) => saved), hasLength(1));
    expect((await repository.getProjectById(snapshot.id))?.revision, 1);
  });

  test('legacy manifests without revision load as revision zero', () async {
    final project = ProjectManifest(
      id: 'legacy',
      name: 'Legacy song',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final json = project.toJson()..remove('revision');
    final versioned = project.copyWith(revision: 7);

    expect(ProjectManifest.fromJson(json).revision, 0);
    expect(ProjectManifest.fromJson(versioned.toJson()).revision, 7);
  });

  test(
    'recovers the previous valid project store after canonical corruption',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-project-recovery-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final repository = FileProjectRepository(rootDirectory: root);
      final first = await repository.createProject(name: 'First project');
      await repository.createProject(name: 'Second project');

      final store = File('${root.path}${Platform.pathSeparator}projects.json');
      await store.writeAsString('{corrupted');

      final recovered = FileProjectRepository(rootDirectory: root);
      final projects = await recovered.getAllProjects();

      expect(projects, hasLength(1));
      expect(projects.single.id, first.id);
      expect(projects.single.name, 'First project');
      expect(await store.readAsString(), contains('First project'));
    },
  );

  for (final corruption in ['non-object', 'duplicate-id', 'invalid-record']) {
    test('rejects $corruption without replacing project files', () async {
      final root = await Directory.systemTemp.createTemp('project-partial-');
      addTearDown(() => root.delete(recursive: true));
      final valid = ProjectManifest(
        id: 'saved',
        name: 'User project',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        lyricDocument: _lyricDocument(text: '保留歌词'),
      );
      final bad = switch (corruption) {
        'non-object' => 'broken',
        'duplicate-id' => valid.copyWith(name: 'Different project').toJson(),
        _ => <String, Object>{'id': 'broken'},
      };
      final original = jsonEncode({
        'version': 1,
        'projects': [valid.toJson(), bad],
      });
      final oldBackup = jsonEncode({'version': 1, 'projects': []});
      final store = File('${root.path}${Platform.pathSeparator}projects.json');
      final backup = File('${store.path}.bak');
      await store.writeAsString(original);
      await backup.writeAsString(oldBackup);
      final repository = FileProjectRepository(rootDirectory: root);

      await expectLater(
        repository.getAllProjects(),
        throwsA(isA<ProjectRepositoryException>()),
      );
      await expectLater(
        repository.getProjectById(valid.id),
        throwsA(isA<ProjectRepositoryException>()),
      );
      await expectLater(
        repository.createProject(name: 'New'),
        throwsA(isA<ProjectRepositoryException>()),
      );
      await expectLater(
        repository.updateProject(valid.copyWith(name: 'Overwrite')),
        throwsA(isA<ProjectRepositoryException>()),
      );
      await expectLater(
        repository.deleteProject(valid.id),
        throwsA(isA<ProjectRepositoryException>()),
      );
      expect(await store.readAsString(), original);
      expect(await backup.readAsString(), oldBackup);
      expect(await File('${store.path}.tmp').exists(), isFalse);

      // After explicit repair, a fresh instance can read and persist projects.
      await store.writeAsString(
        jsonEncode({
          'projects': [valid.toJson()],
        }),
      );
      final repaired = FileProjectRepository(rootDirectory: root);
      expect(
        (await repaired.getProjectById(
          valid.id,
        ))?.lyricDocument?.lines.single.text,
        '保留歌词',
      );
      await repaired.updateProject(valid.copyWith(name: 'Updated'));
      expect((await repaired.getProjectById(valid.id))?.name, 'Updated');
    });
  }

  test('projects survive repository recreation', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-projects-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

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
    expect(restored.revision, project.revision);
  });

  test(
    'auto-links local song metadata when lyrics are first attached',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-projects-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final metadataRepository = _FakeMetadataRepository();
      final session = _FakePlaybackSession();
      final repository = FileProjectRepository(
        rootDirectory: root,
        mediaMetadataRepository: metadataRepository,
        playbackSession: session,
        pathCanonicalizer: const FileAudioPathCanonicalizer(),
      );
      var project = await repository.createProject(name: 'Edited Song');
      project = await repository.updateProject(
        project.copyWith(
          audioAsset: const AudioAsset(
            originalPath: '/music/song.flac',
            format: 'flac',
          ),
          lyricDocument: _lyricDocument(),
        ),
      );
      await pumpEventQueue();

      final saved = metadataRepository.saved;
      expect(saved?.sourcePath, '/music/song.flac');
      expect(saved?.metadata, containsPair('linkedProjectId', project.id));
      expect(saved?.metadata['hasLyrics'], isTrue);
    },
  );

  for (final failureStage in ['read', 'write']) {
    test(
      'reports background association $failureStage failure without losing saved lyrics',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'project-autolink-failure-',
        );
        addTearDown(() => root.delete(recursive: true));
        final failure = StateError('metadata $failureStage failed');
        final metadata = _FakeMetadataRepository();
        if (failureStage == 'read') {
          metadata.readFailure = failure;
        } else {
          metadata.writeFailure = failure;
        }
        final reports = <Object>[];
        final reported = Completer<StackTrace>();
        final session = _FakePlaybackSession();
        final repository = FileProjectRepository(
          rootDirectory: root,
          mediaMetadataRepository: metadata,
          playbackSession: session,
          pathCanonicalizer: const FileAudioPathCanonicalizer(),
          onAutoLinkError: (error, stackTrace) {
            reports.add(error);
            reported.complete(stackTrace);
          },
        );
        final original = await repository.createProject(name: 'Song');
        final updated = await repository.updateProject(
          original.copyWith(
            audioAsset: const AudioAsset(
              originalPath: '/music/song.flac',
              format: 'flac',
            ),
            lyricDocument: _lyricDocument(text: '保留歌词'),
          ),
        );
        final stack = await reported.future.timeout(const Duration(seconds: 5));
        expect(reports, [same(failure)]);
        expect(stack.toString(), contains('_FakeMetadataRepository'));
        expect(metadata.saved, isNull);
        expect(session.currentState.queue, isEmpty);
        final restored = await FileProjectRepository(
          rootDirectory: root,
        ).getProjectById(updated.id);
        expect(restored?.lyricDocument?.lines.single.text, '保留歌词');
        expect(restored?.revision, updated.revision);
      },
    );
  }

  test(
    'corrupt file metadata reports association failure and preserves both stores',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'project-autolink-corrupt-',
      );
      addTearDown(() => root.delete(recursive: true));
      final metadataStore = File(
        '${root.path}${Platform.pathSeparator}media_metadata.json',
      );
      final backup = File('${metadataStore.path}.bak');
      const original = '{"items":["broken"]}';
      const previous = '{"items":[]}';
      await metadataStore.writeAsString(original);
      await backup.writeAsString(previous);
      final reported = Completer<Object>();
      final repository = FileProjectRepository(
        rootDirectory: root,
        mediaMetadataRepository: FileLocalMediaMetadataRepository(
          rootDirectory: root,
        ),
        playbackSession: _FakePlaybackSession(),
        pathCanonicalizer: const FileAudioPathCanonicalizer(),
        onAutoLinkError: (error, _) => reported.complete(error),
      );
      final project = await repository.createProject(name: 'Song');
      final saved = await repository.updateProject(
        project.copyWith(
          audioAsset: const AudioAsset(
            originalPath: '/music/song.flac',
            format: 'flac',
          ),
          lyricDocument: _lyricDocument(text: '安全保存'),
        ),
      );
      expect(
        await reported.future.timeout(const Duration(seconds: 5)),
        isA<FormatException>(),
      );
      expect(await metadataStore.readAsString(), original);
      expect(await backup.readAsString(), previous);
      final restored = await FileProjectRepository(
        rootDirectory: root,
      ).getProjectById(saved.id);
      expect(restored?.lyricDocument?.lines.single.text, '安全保存');
    },
  );

  test(
    'a failing background error observer does not escape the async task',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'project-autolink-observer-',
      );
      addTearDown(() => root.delete(recursive: true));
      final metadata = _FakeMetadataRepository()
        ..readFailure = StateError('metadata failed');
      final notified = Completer<void>();
      final repository = FileProjectRepository(
        rootDirectory: root,
        mediaMetadataRepository: metadata,
        playbackSession: _FakePlaybackSession(),
        pathCanonicalizer: const FileAudioPathCanonicalizer(),
        onAutoLinkError: (_, _) {
          notified.complete();
          throw StateError('observer failed');
        },
      );
      final project = await repository.createProject(name: 'Song');
      await repository.updateProject(
        project.copyWith(
          audioAsset: const AudioAsset(
            originalPath: '/music/song.flac',
            format: 'flac',
          ),
          lyricDocument: _lyricDocument(),
        ),
      );
      await notified.future.timeout(const Duration(seconds: 5));
      await pumpEventQueue();
    },
  );

  test(
    'later lyric saves do not relink or overwrite playlist/user metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-projects-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final metadataRepository = _FakeMetadataRepository();
      final session = _FakePlaybackSession();
      final repository = FileProjectRepository(
        rootDirectory: root,
        mediaMetadataRepository: metadataRepository,
        playbackSession: session,
        pathCanonicalizer: const FileAudioPathCanonicalizer(),
      );
      var project = await repository.createProject(name: 'Edited Song');
      project = await repository.updateProject(
        project.copyWith(
          audioAsset: const AudioAsset(
            originalPath: '/music/song.flac',
            format: 'flac',
          ),
        ),
      );
      await pumpEventQueue();
      expect(metadataRepository.saved, isNull);

      project = await repository.updateProject(
        project.copyWith(lyricDocument: _lyricDocument()),
      );
      await pumpEventQueue();
      expect(metadataRepository.saved?.metadata['linkedProjectId'], project.id);

      final savedBeforeSecondLinkCall = metadataRepository.saved;
      await repository.updateProject(
        project.copyWith(
          lyricDocument: _lyricDocument(text: '改后的词'),
          name: 'Renamed Song',
        ),
      );
      await pumpEventQueue();
      expect(metadataRepository.saved, same(savedBeforeSecondLinkCall));
    },
  );
}

LyricDocument _lyricDocument({String text = '第一句'}) => LyricDocument(
  language: 'zh',
  lines: [
    LyricLine(
      text: text,
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
    ),
  ],
);

class _FakeMetadataRepository implements LocalMediaMetadataRepository {
  LocalMediaMetadata? saved;
  Object? readFailure;
  Object? writeFailure;

  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async {
    final failure = readFailure;
    if (failure != null) throw failure;
    return saved;
  }

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    saved = metadata;
    return metadata;
  }

  @override
  Future<List<LocalMediaMetadata>> getAll() async => [];

  @override
  Future<void> removeForAudio(String sourcePath) async {}

  @override
  Future<String> importArtwork({
    required String sourcePath,
    required String imagePath,
  }) async => imagePath;

  @override
  Future<void> removeManagedArtwork(String? artworkPath) async {}
}

class _FakePlaybackSession implements PlaybackSessionService {
  PlaybackSessionState _state = const PlaybackSessionState();

  @override
  PlaybackSessionState get currentState => _state;

  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  Future<void> updateItem(PlaybackItem item) async {
    final index = _state.queue.indexWhere((queued) => queued.id == item.id);
    if (index < 0) return;
    final queue = [..._state.queue]..[index] = item;
    _state = _state.copyWith(queue: queue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
