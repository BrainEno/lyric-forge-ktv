import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/services/default_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  group('local media metadata in playback', () {
    late Directory directory;
    late _FakeAudioPlayer audio;
    late FileLocalMediaMetadataRepository metadata;
    late DefaultPlaybackSessionService session;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lyricforge-play-meta-');
      audio = _FakeAudioPlayer();
      metadata = FileLocalMediaMetadataRepository(rootDirectory: directory);
      session = DefaultPlaybackSessionService(
        audio,
        localMediaMetadataRepository: metadata,
      );
    });

    tearDown(() async {
      await session.dispose();
      await audio.dispose();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('resolves Unicode title artist and artwork for local songs', () async {
      final audioFile = File('${directory.path}${Platform.pathSeparator}raw.mp3');
      final artwork = File('${directory.path}${Platform.pathSeparator}cover.png');
      await audioFile.writeAsBytes([1]);
      await artwork.writeAsBytes([1]);
      await metadata.save(
        LocalMediaMetadata(
          sourcePath: audioFile.path,
          title: '夜に駆ける / 夜曲 🎵',
          artist: 'YOASOBI · 周杰伦',
          artworkPath: artwork.path,
          updatedAt: DateTime.now(),
        ),
      );

      await session.setQueue([
        _localItem(audioFile.path, title: 'raw'),
      ]);

      final current = session.currentState.currentItem!;
      expect(current.title, '夜に駆ける / 夜曲 🎵');
      expect(current.artist, 'YOASOBI · 周杰伦');
      expect(current.artworkPath, artwork.path);
    });

    test('project-backed playback ignores local file display overrides', () async {
      final audioFile = File('${directory.path}${Platform.pathSeparator}project.mp3');
      await audioFile.writeAsBytes([1]);
      await metadata.save(
        LocalMediaMetadata(
          sourcePath: audioFile.path,
          title: 'Local override',
          updatedAt: DateTime.now(),
        ),
      );

      await session.setQueue([
        PlaybackItem(
          id: 'project:1',
          title: 'Project title',
          projectId: '1',
          audioAsset: AudioAsset(
            originalPath: audioFile.path,
            format: 'mp3',
          ),
        ),
      ]);

      expect(session.currentState.currentItem?.title, 'Project title');
    });

    test('updateItem refreshes metadata without reloading audio', () async {
      final audioFile = File('${directory.path}${Platform.pathSeparator}song.mp3');
      await audioFile.writeAsBytes([1]);
      await session.setQueue([_localItem(audioFile.path)]);
      final loadCount = audio.loadCount;
      final current = session.currentState.currentItem!;

      await session.updateItem(
        current.copyWith(
          title: '新しい表示名',
          artist: 'アーティスト',
        ),
      );

      expect(session.currentState.currentItem?.title, '新しい表示名');
      expect(session.currentState.currentItem?.artist, 'アーティスト');
      expect(audio.loadCount, loadCount);
    });

    test('a project with only original audio is playable', () {
      final project = ProjectManifest(
        id: 'p1',
        name: 'Local song',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
        audioAsset: const AudioAsset(
          originalPath: 'C:/Music/本地歌曲.mp3',
          format: 'mp3',
        ),
      );

      expect(project.canPlay, isTrue);
    });
  });
}

PlaybackItem _localItem(String path, {String title = 'Song'}) {
  return PlaybackItem(
    id: 'local:$path',
    title: title,
    audioAsset: AudioAsset(
      originalPath: path,
      format: 'mp3',
    ),
  );
}

class _FakeAudioPlayer implements AudioPlayerService {
  final _state = StreamController<PlaybackState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  PlaybackState _current = const PlaybackState.idle();
  int loadCount = 0;

  @override
  PlaybackState get currentState => _current;

  @override
  Stream<PlaybackState> get stateStream => _state.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    loadCount += 1;
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
    _state.add(_current);
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> play() async {
    _current = _current.copyWith(isPlaying: true);
    _state.add(_current);
  }

  @override
  Future<void> pause() async {
    _current = _current.copyWith(isPlaying: false);
    _state.add(_current);
  }

  @override
  Future<void> stop() async {
    _current = const PlaybackState.idle();
    _state.add(_current);
  }

  @override
  Future<void> seek(Duration position) async {
    _current = _current.copyWith(position: position);
    _positions.add(position);
    _state.add(_current);
  }

  @override
  Future<void> switchSource(AudioSourceType source) async {
    _current = _current.copyWith(currentSource: source);
    _state.add(_current);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _current = _current.copyWith(speed: speed);
    _state.add(_current);
  }

  @override
  Future<void> setVolume(double volume) async {
    _current = _current.copyWith(volume: volume);
    _state.add(_current);
  }

  @override
  Future<void> dispose() async {
    await _state.close();
    await _positions.close();
    await _durations.close();
  }
}
