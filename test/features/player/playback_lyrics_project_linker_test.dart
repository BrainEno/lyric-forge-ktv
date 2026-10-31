import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_project_linker.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('links generated lyrics and refreshes matching queued songs', () async {
    const audioPath = '/music/song.mp3';
    final metadataRepository = _FakeMetadataRepository(
      LocalMediaMetadata(
        sourcePath: audioPath,
        title: 'User title',
        updatedAt: DateTime(2026),
        metadata: const {'custom': 'preserved'},
      ),
    );
    final session = _FakePlaybackSession(
      PlaybackSessionState(
        queue: [
          _item('song-1', audioPath),
          _item('song-2', audioPath),
          _item('other-song', '/music/other.mp3'),
        ],
        currentIndex: 0,
      ),
    );

    await linkPlaybackLyricsProject(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      audioPath: audioPath,
      projectId: 'lyrics-project',
      metadataRepository: metadataRepository,
      playbackSession: session,
    );

    expect(
      metadataRepository.saved?.metadata,
      containsPair('custom', 'preserved'),
    );
    expect(
      metadataRepository.saved?.metadata,
      containsPair('linkedProjectId', 'lyrics-project'),
    );
    expect(metadataRepository.saved?.metadata['hasLyrics'], isTrue);
    expect(metadataRepository.saved?.title, 'User title');
    expect(session.currentState.queue[0].hasLyrics, isTrue);
    expect(session.currentState.queue[1].hasLyrics, isTrue);
    expect(session.currentState.queue[2].hasLyrics, isFalse);
  });

  test('creates song metadata when no overrides exist', () async {
    final metadataRepository = _FakeMetadataRepository();
    final session = _FakePlaybackSession(const PlaybackSessionState());

    await linkPlaybackLyricsProject(
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      audioPath: '/music/song.mp3',
      projectId: 'lyrics-project',
      metadataRepository: metadataRepository,
      playbackSession: session,
    );

    expect(metadataRepository.saved?.sourcePath, '/music/song.mp3');
    expect(
      metadataRepository.saved?.metadata['linkedProjectId'],
      'lyrics-project',
    );
  });
}

PlaybackItem _item(String id, String path) => PlaybackItem(
  id: id,
  title: id,
  audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
);

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

class _FakePlaybackSession implements PlaybackSessionService {
  @override
  PlaybackSessionState currentState;

  _FakePlaybackSession(this.currentState);

  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  Future<void> updateItem(PlaybackItem item) async {
    final index = currentState.queue.indexWhere(
      (queued) => queued.id == item.id,
    );
    if (index < 0) return;
    final queue = [...currentState.queue]..[index] = item;
    currentState = currentState.copyWith(queue: queue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
