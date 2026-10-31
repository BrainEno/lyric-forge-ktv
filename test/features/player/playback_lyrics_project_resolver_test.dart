import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_project_resolver.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

void main() {
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

  PlaybackItem item(String path, {String? projectId}) => PlaybackItem(
    id: 'item-1',
    title: 'song',
    audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
    projectId: projectId,
    hasLyrics: true,
  );

  ProjectManifest project(
    String id,
    String audioPath, {
    bool withLyrics = true,
  }) => ProjectManifest(
    id: id,
    name: id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    audioAsset: AudioAsset(originalPath: audioPath, format: 'mp3'),
    lyricDocument: withLyrics ? lyricDocument : null,
  );

  test('resolves the persisted linked project without rewriting', () async {
    const audioPath = '/music/song.mp3';
    final metadataRepository = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        updatedAt: DateTime(2026),
        metadata: const {
          'linkedProjectId': 'project-linked',
          'custom': 'preserved',
        },
      ),
    );

    final resolved = await resolvePlaybackLyricsProjectId(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath),
      projectRepository: _FakeProjectRepository([
        project('project-linked', audioPath),
      ]),
      metadataRepository: metadataRepository,
    );

    expect(resolved, 'project-linked');
    expect(metadataRepository.saved, isNull);
  });

  test('prefers the item own project id', () async {
    const audioPath = '/music/song.mp3';
    final metadataRepository = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'project-linked'},
      ),
    );

    final resolved = await resolvePlaybackLyricsProjectId(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath, projectId: 'project-direct'),
      projectRepository: _FakeProjectRepository([
        project('project-direct', audioPath),
        project('project-linked', audioPath),
      ]),
      metadataRepository: metadataRepository,
    );

    expect(resolved, 'project-direct');
    expect(metadataRepository.saved, isNull);
  });

  test(
    'falls back to the audio path project and repairs a stale link',
    () async {
      const audioPath = '/music/song.mp3';
      final metadataRepository = _FakeMetadataRepository(
        LocalMediaMetadata(
          sourcePath: audioPath,
          title: 'User title',
          updatedAt: DateTime(2026),
          metadata: const {
            'linkedProjectId': 'project-deleted',
            'custom': 'preserved',
          },
        ),
      );

      final resolved = await resolvePlaybackLyricsProjectId(
        pathCanonicalizer: const FileAudioPathCanonicalizer(),
        item: item(audioPath),
        projectRepository: _FakeProjectRepository([
          project('project-other', '/music/other.mp3'),
          project('project-repaired', audioPath),
        ]),
        metadataRepository: metadataRepository,
      );

      expect(resolved, 'project-repaired');
      final saved = metadataRepository.saved;
      expect(saved?.sourcePath, audioPath);
      expect(saved?.title, 'User title');
      expect(saved?.metadata, containsPair('custom', 'preserved'));
      expect(
        saved?.metadata,
        containsPair('linkedProjectId', 'project-repaired'),
      );
      expect(saved?.metadata['hasLyrics'], isTrue);
    },
  );

  test('clears a dead link when no project matches the audio path', () async {
    const audioPath = '/music/song.mp3';
    final metadataRepository = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        title: 'User title',
        updatedAt: DateTime(2026),
        metadata: const {
          'linkedProjectId': 'project-deleted',
          'hasLyrics': true,
          'custom': 'preserved',
        },
      ),
    );

    final resolved = await resolvePlaybackLyricsProjectId(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath),
      projectRepository: _FakeProjectRepository([
        project('project-other', '/music/other.mp3'),
      ]),
      metadataRepository: metadataRepository,
    );

    expect(resolved, isNull);
    final saved = metadataRepository.saved;
    expect(saved?.title, 'User title');
    expect(saved?.metadata, containsPair('custom', 'preserved'));
    expect(saved?.metadata.containsKey('linkedProjectId'), isFalse);
    expect(saved?.metadata.containsKey('hasLyrics'), isFalse);
  });

  test('does not match draft projects without lyrics', () async {
    const audioPath = '/music/song.mp3';
    final metadataRepository = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'project-draft'},
      ),
    );

    final resolved = await resolvePlaybackLyricsProjectId(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath),
      projectRepository: _FakeProjectRepository([
        project('project-draft', audioPath, withLyrics: false),
      ]),
      metadataRepository: metadataRepository,
    );

    expect(resolved, isNull);
    final saved = metadataRepository.saved;
    expect(saved?.metadata.containsKey('linkedProjectId'), isFalse);
  });

  test('leaves untouched media when no link and no project match', () async {
    const audioPath = '/music/song.mp3';
    final metadataRepository = _FakeMetadataRepository();

    final resolved = await resolvePlaybackLyricsProjectId(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath),
      projectRepository: _FakeProjectRepository(const []),
      metadataRepository: metadataRepository,
    );

    expect(resolved, isNull);
    expect(metadataRepository.saved, isNull);
  });

  test('remote streams never resolve a local lyrics project', () async {
    final metadataRepository = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: '/music/song.mp3',
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'project-linked'},
      ),
    );

    final resolved = await resolvePlaybackLyricsProjectId(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: PlaybackItem(
        id: 'stream-1',
        title: 'stream',
        audioAsset: AudioAsset(originalPath: '/music/song.mp3', format: 'mp3'),
        hasLyrics: true,
        streamUri: Uri.parse('https://example.com/song.mp3'),
      ),
      projectRepository: _FakeProjectRepository(const []),
      metadataRepository: metadataRepository,
    );

    expect(resolved, isNull);
    expect(metadataRepository.saved, isNull);
  });

  test('reports repaired and cleared links in the structured result', () async {
    const audioPath = '/music/song.mp3';

    final repaired = await resolvePlaybackLyrics(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath),
      projectRepository: _FakeProjectRepository([
        project('project-repaired', audioPath),
      ]),
      metadataRepository: _FakeMetadataRepository(
        LocalMediaMetadata(
          sourcePath: audioPath,
          updatedAt: DateTime(2026),
          metadata: const {'linkedProjectId': 'project-deleted'},
        ),
      ),
    );

    expect(repaired.projectId, 'project-repaired');
    expect(repaired.hasLyrics, isTrue);
    expect(repaired.repairedLink, isTrue);
    expect(repaired.clearedLink, isFalse);

    final cleared = await resolvePlaybackLyrics(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: item(audioPath),
      projectRepository: _FakeProjectRepository(const []),
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
    );

    expect(cleared.projectId, isNull);
    expect(cleared.hasLyrics, isFalse);
    expect(cleared.clearedLink, isTrue);
    expect(cleared.repairedLink, isFalse);
  });

  test('discovers lyrics for an item enqueued before the project existed',
      () async {
    const audioPath = '/music/song.mp3';

    final resolution = await resolvePlaybackLyrics(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      item: PlaybackItem(
        id: 'item-1',
        title: 'song',
        audioAsset: const AudioAsset(originalPath: audioPath, format: 'mp3'),
      ),
      projectRepository: _FakeProjectRepository([
        project('project-late', audioPath),
      ]),
      metadataRepository: _FakeMetadataRepository(),
    );

    expect(resolution.projectId, 'project-late');
    expect(resolution.hasLyrics, isTrue);
  });
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
