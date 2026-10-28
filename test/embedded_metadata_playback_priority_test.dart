import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/services/default_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/data/services/library_metadata_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/embedded_audio_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/embedded_audio_metadata_reader.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('user overrides win over embedded tags and filename fallback', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-priority-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audioFile = File('${root.path}${Platform.pathSeparator}乱码文件名.mp3');
    await audioFile.writeAsBytes(const [1, 2, 3]);

    final library = FileLocalMediaLibraryRepository(
      rootDirectory: Directory('${root.path}${Platform.pathSeparator}library'),
      metadataReader: const _StaticEmbeddedReader(),
    );
    await library.addPaths([audioFile.path]);

    final overrides = FileLocalMediaMetadataRepository(
      rootDirectory: Directory('${root.path}${Platform.pathSeparator}overrides'),
    );
    await overrides.save(
      LocalMediaMetadata(
        sourcePath: audioFile.path,
        title: '用户修正标题 中文 🎵',
        artist: 'ユーザー修正アーティスト',
        updatedAt: DateTime.now(),
      ),
    );

    final audio = _FakeAudioPlayer();
    final base = DefaultPlaybackSessionService(
      audio,
      localMediaMetadataRepository: overrides,
    );
    final session = LibraryMetadataPlaybackSessionService(
      delegate: base,
      libraryRepository: library,
    );
    addTearDown(session.dispose);

    await session.setQueue([
      PlaybackItem(
        id: 'local:${audioFile.path}',
        title: '乱码文件名',
        audioAsset: AudioAsset(originalPath: audioFile.path, format: 'mp3'),
      ),
    ]);

    final current = session.currentState.currentItem!;
    expect(current.title, '用户修正标题 中文 🎵');
    expect(current.artist, 'ユーザー修正アーティスト');
    expect(current.artworkPath, 'embedded-cover.jpg');
  });

  test('embedded tags win over filename fallback without user overrides', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-priority-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audioFile = File('${root.path}${Platform.pathSeparator}raw-name.flac');
    await audioFile.writeAsBytes(const [1]);
    final library = FileLocalMediaLibraryRepository(
      rootDirectory: Directory('${root.path}${Platform.pathSeparator}library'),
      metadataReader: const _StaticEmbeddedReader(),
    );
    await library.addPaths([audioFile.path]);

    final audio = _FakeAudioPlayer();
    final base = DefaultPlaybackSessionService(audio);
    final session = LibraryMetadataPlaybackSessionService(
      delegate: base,
      libraryRepository: library,
    );
    addTearDown(session.dispose);

    await session.playItem(
      PlaybackItem(
        id: 'local:${audioFile.path}',
        title: 'raw-name',
        audioAsset: AudioAsset(originalPath: audioFile.path, format: 'flac'),
      ),
    );

    expect(session.currentState.currentItem?.title, '内嵌标题');
    expect(session.currentState.currentItem?.artist, '嵌入アーティスト');
  });
}

class _StaticEmbeddedReader implements EmbeddedAudioMetadataReader {
  const _StaticEmbeddedReader();

  @override
  Future<EmbeddedAudioMetadata> read(String sourcePath) async {
    final file = File(sourcePath);
    final stat = await file.stat();
    return EmbeddedAudioMetadata(
      sourcePath: file.absolute.path,
      title: '内嵌标题',
      artist: '嵌入アーティスト',
      album: 'Embedded Album',
      artworkPath: 'embedded-cover.jpg',
      sourceSizeBytes: stat.size,
      sourceModifiedAt: stat.modified,
      scannedAt: DateTime.now(),
    );
  }
}

class _FakeAudioPlayer implements AudioPlayerService {
  final _states = StreamController<PlaybackState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  PlaybackState _current = const PlaybackState.idle();

  @override
  PlaybackState get currentState => _current;
  @override
  Stream<PlaybackState> get stateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    _current = PlaybackState(
      isPlaying: false,
      isBuffering: false,
      isCompleted: false,
      isLoading: false,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      bufferedPosition: Duration.zero,
      speed: 1,
      volume: 1,
      currentSource: preferredSource,
    );
    _states.add(_current);
  }

  @override
  Future<void> loadAudioUri({required Uri uri, AudioSourceType source = AudioSourceType.original}) async {}
  @override
  Future<void> play() async {
    _current = _current.copyWith(isPlaying: true);
    _states.add(_current);
  }
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {
    _current = _current.copyWith(position: position);
    _positions.add(position);
  }
  @override
  Future<void> switchSource(AudioSourceType source) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {
    await _states.close();
    await _positions.close();
    await _durations.close();
  }
}
