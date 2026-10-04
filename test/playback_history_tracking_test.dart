import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/default_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  group('DefaultPlaybackSessionService history tracking', () {
    late _FakeAudioPlayer audio;
    late _FakePlayHistoryRepository history;
    late DefaultPlaybackSessionService session;

    setUp(() {
      audio = _FakeAudioPlayer();
      history = _FakePlayHistoryRepository();
      session = DefaultPlaybackSessionService(
        audio,
        playHistoryRepository: history,
      );
    });

    tearDown(() async {
      await session.dispose();
      await audio.dispose();
    });

    test('seek persists the current local track resume position', () async {
      await session.setQueue([_localItem('song')]);

      await session.seek(const Duration(seconds: 42));

      expect(history.latest?.filePath, '/tmp/song.mp3');
      expect(history.latest?.lastPosition, const Duration(seconds: 42));
    });

    test('position stream periodically updates local history', () async {
      await session.setQueue([_localItem('song')]);
      history.saved.clear();

      audio.emitPosition(const Duration(seconds: 16));
      await Future<void>.delayed(Duration.zero);

      expect(history.saved, isNotEmpty);
      expect(history.latest?.lastPosition, const Duration(seconds: 16));
    });

    test('completed tracks resume from the beginning instead of the end', () async {
      await session.setQueue([_localItem('song')]);

      await session.seek(const Duration(minutes: 2, seconds: 59));

      expect(history.latest?.lastPosition, Duration.zero);
    });

    test('project-backed playback is excluded from local recent history', () async {
      await session.setQueue([_projectItem('project-song')]);
      history.saved.clear();

      await session.seek(const Duration(seconds: 30));

      expect(history.saved, isEmpty);
    });

    test('switching tracks preserves the previous track progress', () async {
      await session.setQueue([
        _localItem('first'),
        _localItem('second'),
      ]);
      await session.seek(const Duration(seconds: 61));

      await session.skipNext();

      final first = history.saved.lastWhere(
        (entry) => entry.filePath == '/tmp/first.mp3',
      );
      expect(first.lastPosition, const Duration(seconds: 61));
      expect(history.latest?.filePath, '/tmp/second.mp3');
    });
  });
}

PlaybackItem _localItem(String id) {
  return PlaybackItem(
    id: 'local:$id',
    title: id,
    artist: 'Artist',
    audioAsset: AudioAsset(
      originalPath: '/tmp/$id.mp3',
      format: 'mp3',
    ),
    preferredSource: AudioSourceType.original,
  );
}

PlaybackItem _projectItem(String id) {
  return PlaybackItem(
    id: 'project:$id',
    title: id,
    projectId: id,
    audioAsset: AudioAsset(
      originalPath: '/tmp/$id.mp3',
      format: 'mp3',
    ),
    preferredSource: AudioSourceType.original,
  );
}

class _FakePlayHistoryRepository implements PlayHistoryRepository {
  final List<PlayHistory> saved = [];

  PlayHistory? get latest => saved.isEmpty ? null : saved.last;

  @override
  Future<void> savePlayHistory(PlayHistory history) async {
    saved.add(history);
  }

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    return saved.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<void> clearPlayHistory() async => saved.clear();

  @override
  Future<void> removePlayHistory(String id) async {
    saved.removeWhere((history) => history.id == id);
  }

  @override
  Future<PlayHistory?> getPlayHistoryById(String id) async {
    for (final entry in saved.reversed) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

class _FakeAudioPlayer implements AudioPlayerService {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  PlaybackState _state = const PlaybackState.idle();

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    _state = PlaybackState(
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
    _stateController.add(_state);
    _durationController.add(_state.duration);
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> play() async {
    _state = _state.copyWith(isPlaying: true);
    _stateController.add(_state);
  }

  @override
  Future<void> pause() async {
    _state = _state.copyWith(isPlaying: false);
    _stateController.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = const PlaybackState.idle();
    _stateController.add(_state);
  }

  @override
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position);
    _positionController.add(position);
    _stateController.add(_state);
  }

  void emitPosition(Duration position) {
    _state = _state.copyWith(position: position);
    _positionController.add(position);
  }

  @override
  Future<void> switchSource(AudioSourceType source) async {
    _state = _state.copyWith(currentSource: source);
    _stateController.add(_state);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _state = _state.copyWith(speed: speed);
    _stateController.add(_state);
  }

  @override
  Future<void> setVolume(double volume) async {
    _state = _state.copyWith(volume: volume);
    _stateController.add(_state);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}
