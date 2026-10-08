import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_project_resolver.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

void main() {
  test('project playback keeps its direct project id', () async {
    final projects = _FakeProjectRepository([
      _project('direct-project', withLyrics: false),
    ]);

    final result = await resolvePlaybackLyricsProjectId(
      item: _item(projectId: 'direct-project'),
      projectRepository: projects,
      metadataRepository: _FakeMetadataRepository(),
    );

    expect(result, 'direct-project');
  });

  test('local playback resolves linkedProjectId when linked project has lyrics',
      () async {
    final metadata = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: '/music/song.mp3',
        updatedAt: DateTime(2026, 10, 8),
        metadata: const {'linkedProjectId': 'lyrics-project'},
      ),
    );
    final projects = _FakeProjectRepository([
      _project('lyrics-project', withLyrics: true),
    ]);

    final result = await resolvePlaybackLyricsProjectId(
      item: _item(hasLyrics: true),
      projectRepository: projects,
      metadataRepository: metadata,
    );

    expect(result, 'lyrics-project');
  });

  test('stale or lyric-less local links do not expose a KTV action', () async {
    final metadata = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: '/music/song.mp3',
        updatedAt: DateTime(2026, 10, 8),
        metadata: const {'linkedProjectId': 'empty-project'},
      ),
    );
    final projects = _FakeProjectRepository([
      _project('empty-project', withLyrics: false),
    ]);

    expect(
      await resolvePlaybackLyricsProjectId(
        item: _item(hasLyrics: true),
        projectRepository: projects,
        metadataRepository: metadata,
      ),
      isNull,
    );
  });
}

PlaybackItem _item({String? projectId, bool hasLyrics = false}) => PlaybackItem(
      id: 'song',
      title: 'Song',
      projectId: projectId,
      hasLyrics: hasLyrics,
      audioAsset: const AudioAsset(
        originalPath: '/music/song.mp3',
        format: 'mp3',
      ),
    );

ProjectManifest _project(String id, {required bool withLyrics}) {
  final now = DateTime(2026, 10, 8);
  return ProjectManifest(
    id: id,
    name: id,
    createdAt: now,
    updatedAt: now,
    lyricDocument: withLyrics
        ? const LyricDocument(
            language: 'en',
            lines: [
              LyricLine(
                text: 'Hello',
                startTime: Duration.zero,
                endTime: Duration(seconds: 2),
              ),
            ],
          )
        : null,
  );
}

class _FakeMetadataRepository implements LocalMediaMetadataRepository {
  final LocalMediaMetadata? metadata;

  _FakeMetadataRepository([this.metadata]);

  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => metadata;

  @override
  Future<List<LocalMediaMetadata>> getAll() async =>
      metadata == null ? const [] : [metadata!];

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async => metadata;

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
  final Map<String, ProjectManifest> projects;

  _FakeProjectRepository(Iterable<ProjectManifest> values)
      : projects = {for (final project in values) project.id: project};

  @override
  Future<ProjectManifest?> getProjectById(String id) async => projects[id];

  @override
  Future<List<ProjectManifest>> getAllProjects() async => projects.values.toList();

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async =>
      projects.values.take(limit).toList();

  @override
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  }) => throw UnimplementedError();

  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) =>
      throw UnimplementedError();

  @override
  Future<void> deleteProject(String id) => throw UnimplementedError();
}
