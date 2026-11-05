import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => saved;

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async {
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
