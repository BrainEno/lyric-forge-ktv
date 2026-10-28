import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_availability.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_lyrics_availability_sync.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

void main() {
  const audioPath = '/music/song.mp3';
  const lyricDocument = LyricDocument(
    language: 'zh',
    lines: [
      LyricLine(
        text: '一',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
      ),
    ],
  );

  PlaybackItem item({bool hasLyrics = true, String? projectId}) => PlaybackItem(
    id: 'item-1',
    title: 'song',
    audioAsset: const AudioAsset(originalPath: audioPath, format: 'mp3'),
    projectId: projectId,
    hasLyrics: hasLyrics,
  );

  ProjectManifest project(
    String id, {
    String path = audioPath,
    bool withLyrics = true,
  }) => ProjectManifest(
    id: id,
    name: id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
    lyricDocument: withLyrics ? lyricDocument : null,
  );

  test('retracts the queue flag when a dead lyric link is cleared', () async {
    final metadata = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        updatedAt: DateTime(2026),
        metadata: const {
          'linkedProjectId': 'project-deleted',
          'hasLyrics': true,
        },
      ),
    );
    final session = _RecordingSession();

    final resolution = await resolveAndSyncPlaybackLyrics(
      item: item(),
      projectRepository: _FakeProjectRepository(const []),
      metadataRepository: metadata,
      playbackSession: session,
    );

    expect(resolution.projectId, isNull);
    expect(resolution.hasLyrics, isFalse);
    expect(resolution.clearedLink, isTrue);
    expect(metadata.saved?.metadata.containsKey('linkedProjectId'), isFalse);
    expect(session.updates, hasLength(1));
    expect(session.updates.single.id, 'item-1');
    expect(session.updates.single.hasLyrics, isFalse);
  });

  test('raises the flag when a lyric project appears after enqueue', () async {
    final metadata = _FakeMetadataRepository();
    final session = _RecordingSession();

    final resolution = await resolveAndSyncPlaybackLyrics(
      item: item(hasLyrics: false),
      projectRepository: _FakeProjectRepository([project('project-found')]),
      metadataRepository: metadata,
      playbackSession: session,
    );

    expect(resolution.projectId, 'project-found');
    expect(resolution.hasLyrics, isTrue);
    expect(resolution.repairedLink, isTrue);
    expect(session.updates, hasLength(1));
    expect(session.updates.single.hasLyrics, isTrue);
    expect(
      metadata.saved?.metadata,
      containsPair('linkedProjectId', 'project-found'),
    );
  });

  test('leaves a matching flag untouched', () async {
    final metadata = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'project-linked'},
      ),
    );
    final session = _RecordingSession();

    final resolution = await resolveAndSyncPlaybackLyrics(
      item: item(),
      projectRepository: _FakeProjectRepository([project('project-linked')]),
      metadataRepository: metadata,
      playbackSession: session,
    );

    expect(resolution.projectId, 'project-linked');
    expect(session.updates, isEmpty);
  });

  test('project playback mirrors the project lyric document', () async {
    final session = _RecordingSession();

    final resolution = await resolveAndSyncPlaybackLyrics(
      item: item(hasLyrics: false, projectId: 'project-1'),
      projectRepository: _FakeProjectRepository([project('project-1')]),
      metadataRepository: _FakeMetadataRepository(),
      playbackSession: session,
    );

    expect(resolution.projectId, 'project-1');
    expect(resolution.hasLyrics, isTrue);
    expect(session.updates.single.hasLyrics, isTrue);
  });

  test('a deleted project retracts project playback lyrics', () async {
    final session = _RecordingSession();

    final resolution = await resolveAndSyncPlaybackLyrics(
      item: item(projectId: 'project-gone'),
      projectRepository: _FakeProjectRepository(const []),
      metadataRepository: _FakeMetadataRepository(),
      playbackSession: session,
    );

    expect(resolution.projectId, isNull);
    expect(resolution.hasLyrics, isFalse);
    expect(session.updates.single.hasLyrics, isFalse);
  });

  test('never rewrites the flag of a remote stream', () async {
    final session = _RecordingSession();

    final resolution = await resolveAndSyncPlaybackLyrics(
      item: PlaybackItem(
        id: 'stream-1',
        title: 'stream',
        audioAsset: const AudioAsset(originalPath: audioPath, format: 'mp3'),
        streamUri: Uri.parse('https://example.com/song.mp3'),
        hasLyrics: true,
      ),
      projectRepository: _FakeProjectRepository([project('project-linked')]),
      metadataRepository: _FakeMetadataRepository(),
      playbackSession: session,
    );

    expect(resolution.projectId, isNull);
    expect(session.updates, isEmpty);
  });

  testWidgets('syncs the current queue item when the session changes',
      (tester) async {
    final session = _StreamingSession(
      PlaybackSessionState(queue: [item()], currentIndex: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackLyricsAvailabilitySync(
          playbackSession: session,
          projectRepository: _FakeProjectRepository([
            project('project-late', path: '/music/other.mp3'),
          ]),
          metadataRepository: _FakeMetadataRepository(
            LocalMediaMetadata(
              sourcePath: audioPath,
              updatedAt: DateTime(2026),
              metadata: const {
                'linkedProjectId': 'project-deleted',
                'hasLyrics': true,
              },
            ),
          ),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.updates, hasLength(1));
    expect(session.updates.single.id, 'item-1');
    expect(session.updates.single.hasLyrics, isFalse);

    session.push(
      PlaybackSessionState(
        queue: [
          PlaybackItem(
            id: 'item-2',
            title: 'next',
            audioAsset: const AudioAsset(
              originalPath: '/music/other.mp3',
              format: 'mp3',
            ),
          ),
        ],
        currentIndex: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(session.updates, hasLength(2));
    expect(session.updates.last.id, 'item-2');
    expect(session.updates.last.hasLyrics, isTrue);
  });
}

class _StreamingSession implements PlaybackSessionService {
  _StreamingSession(this.state);

  PlaybackSessionState state;
  final _controller = StreamController<PlaybackSessionState>.broadcast();
  final List<PlaybackItem> updates = [];

  void push(PlaybackSessionState next) {
    state = next;
    _controller.add(next);
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => state;

  @override
  Future<void> updateItem(PlaybackItem item) async {
    updates.add(item);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingSession implements PlaybackSessionService {
  final List<PlaybackItem> updates = [];

  @override
  Future<void> updateItem(PlaybackItem item) async {
    updates.add(item);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMetadataRepository implements LocalMediaMetadataRepository {
  final LocalMediaMetadata? existing;
  LocalMediaMetadata? saved;

  _FakeMetadataRepository([this.existing]);

  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => existing;

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async {
    saved = metadata;
    return metadata;
  }

  @override
  Future<List<LocalMediaMetadata>> getAll() async => const [];

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

class _FakeProjectRepository implements ProjectRepository {
  final List<ProjectManifest> projects;

  _FakeProjectRepository(this.projects);

  @override
  Future<List<ProjectManifest>> getAllProjects() async => projects;

  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
