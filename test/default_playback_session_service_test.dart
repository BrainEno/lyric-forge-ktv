import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/default_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  group('DefaultPlaybackSessionService queue management', () {
    late _FakeAudioPlayer audio;
    late DefaultPlaybackSessionService session;

    setUp(() {
      audio = _FakeAudioPlayer();
      session = DefaultPlaybackSessionService(audio, random: Random(42));
    });

    tearDown(() async {
      await session.dispose();
      await audio.dispose();
    });

    test('playAt switches to an existing queue item', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      await session.setQueue(items);

      await session.playAt(2);

      expect(session.currentState.currentIndex, 2);
      expect(session.currentState.currentItem?.id, 'c');
      expect(audio.loadedIds, ['a', 'c']);
    });

    test('removing an item before current keeps the same song active', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      await session.setQueue(items, startIndex: 2);
      final loadCount = audio.loadedIds.length;

      await session.removeAt(0);

      expect(session.currentState.queue.map((item) => item.id), ['b', 'c']);
      expect(session.currentState.currentIndex, 1);
      expect(session.currentState.currentItem?.id, 'c');
      expect(audio.loadedIds.length, loadCount);
    });

    test('removing current advances to the next item', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      await session.setQueue(items, startIndex: 1);

      await session.removeAt(1);

      expect(session.currentState.queue.map((item) => item.id), ['a', 'c']);
      expect(session.currentState.currentIndex, 1);
      expect(session.currentState.currentItem?.id, 'c');
      expect(audio.loadedIds.last, 'c');
    });

    test('removing last current item falls back to previous item', () async {
      final items = [_item('a'), _item('b')];
      await session.setQueue(items, startIndex: 1);

      await session.removeAt(1);

      expect(session.currentState.queue.map((item) => item.id), ['a']);
      expect(session.currentState.currentIndex, 0);
      expect(session.currentState.currentItem?.id, 'a');
      expect(audio.loadedIds.last, 'a');
    });

    test('removing the only item stops playback', () async {
      await session.setQueue([_item('a')]);

      await session.removeAt(0);

      expect(session.currentState.queue, isEmpty);
      expect(session.currentState.currentIndex, -1);
      expect(audio.stopCount, 1);
    });

    test('moving items preserves the active song without reloading audio', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      await session.setQueue(items, startIndex: 1);
      final loadCount = audio.loadedIds.length;

      await session.moveItem(1, 2);

      expect(session.currentState.queue.map((item) => item.id), ['a', 'c', 'b']);
      expect(session.currentState.currentIndex, 2);
      expect(session.currentState.currentItem?.id, 'b');
      expect(audio.loadedIds.length, loadCount);
    });

    test('clearQueue keeps current song by default', () async {
      await session.setQueue([_item('a'), _item('b'), _item('c')], startIndex: 1);

      await session.clearQueue();

      expect(session.currentState.queue.map((item) => item.id), ['b']);
      expect(session.currentState.currentIndex, 0);
      expect(audio.stopCount, 0);
    });

    test('clearQueue can stop and remove everything', () async {
      await session.setQueue([_item('a'), _item('b')]);

      await session.clearQueue(keepCurrent: false);

      expect(session.currentState.queue, isEmpty);
      expect(session.currentState.currentIndex, -1);
      expect(audio.stopCount, 1);
    });

    test('shuffle preserves current prefix and disabling restores order', () async {
      final items = [_item('a'), _item('b'), _item('c'), _item('d'), _item('e')];
      await session.setQueue(items, startIndex: 1);

      await session.setShuffleEnabled(true);

      expect(session.currentState.shuffleEnabled, isTrue);
      expect(session.currentState.currentItem?.id, 'b');
      expect(session.currentState.queue.take(2).map((item) => item.id), ['a', 'b']);
      expect(
        session.currentState.queue.skip(2).map((item) => item.id).toSet(),
        {'c', 'd', 'e'},
      );

      await session.setShuffleEnabled(false);

      expect(session.currentState.shuffleEnabled, isFalse);
      expect(session.currentState.queue.map((item) => item.id),
          ['a', 'b', 'c', 'd', 'e']);
      expect(session.currentState.currentItem?.id, 'b');
    });

    test('repeat all wraps manual next from the end to the first song', () async {
      await session.setQueue([_item('a'), _item('b')], startIndex: 1);
      await session.setRepeatMode(PlaybackRepeatMode.all);

      await session.skipNext();

      expect(session.currentState.currentItem?.id, 'a');
      expect(audio.loadedIds.last, 'a');
    });

    test('repeat all wraps previous from the first song when near start', () async {
      await session.setQueue([_item('a'), _item('b'), _item('c')]);
      await audio.setPosition(const Duration(seconds: 2));
      await session.setRepeatMode(PlaybackRepeatMode.all);

      await session.skipPrevious();

      expect(session.currentState.currentItem?.id, 'c');
      expect(audio.loadedIds.last, 'c');
    });

    test('repeat one reloads the same song after automatic completion', () async {
      await session.setQueue([_item('a'), _item('b')]);
      await session.setRepeatMode(PlaybackRepeatMode.one);
      final before = audio.loadedIds.length;

      await audio.complete();
      await _flushAsyncPlayback();

      expect(session.currentState.currentItem?.id, 'a');
      expect(audio.loadedIds.length, greaterThan(before));
      expect(audio.loadedIds.last, 'a');
    });

    test('repeat one does not block an explicit manual next action', () async {
      await session.setQueue([_item('a'), _item('b')]);
      await session.setRepeatMode(PlaybackRepeatMode.one);

      await session.skipNext();

      expect(session.currentState.currentItem?.id, 'b');
      expect(audio.loadedIds.last, 'b');
    });

    test('repeat all advances automatically from last to first', () async {
      await session.setQueue([_item('a'), _item('b')], startIndex: 1);
      await session.setRepeatMode(PlaybackRepeatMode.all);

      await audio.complete();
      await _flushAsyncPlayback();

      expect(session.currentState.currentItem?.id, 'a');
      expect(audio.loadedIds.last, 'a');
    });

    test('queue edits retain playback mode state', () async {
      await session.setQueue([_item('a'), _item('b'), _item('c')]);
      await session.setShuffleEnabled(true);
      await session.setRepeatMode(PlaybackRepeatMode.all);

      await session.enqueue(_item('d'));
      await session.removeAt(1);

      expect(session.currentState.shuffleEnabled, isTrue);
      expect(session.currentState.repeatMode, PlaybackRepeatMode.all);
    });
  });
}

Future<void> _flushAsyncPlayback() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

PlaybackItem _item(String id) {
  return PlaybackItem(
    id: id,
    title: id.toUpperCase(),
    audioAsset: AudioAsset(
      originalPath: '/tmp/$id.mp3',
      format: 'mp3',
      metadata: {'testId': id},
    ),
  );
}

class _FakeAudioPlayer implements AudioPlayerService {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  PlaybackState _state = const PlaybackState.idle();
  final List<String> loadedIds = [];
  int stopCount = 0;

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
    loadedIds.add(audioAsset.metadata['testId'] as String);
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
  }

  Future<void> complete() async {
    _state = _state.copyWith(
      isPlaying: false,
      isCompleted: true,
      position: _state.duration ?? _state.position,
    );
    _stateController.add(_state);
  }

  Future<void> setPosition(Duration position) async {
    _state = _state.copyWith(position: position, isCompleted: false);
    _positionController.add(position);
    _stateController.add(_state);
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> play() async {
    _state = _state.copyWith(isPlaying: true, isCompleted: false);
    _stateController.add(_state);
  }

  @override
  Future<void> pause() async {
    _state = _state.copyWith(isPlaying: false);
    _stateController.add(_state);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _state = const PlaybackState.idle();
    _stateController.add(_state);
  }

  @override
  Future<void> seek(Duration position) async {
    _state = _state.copyWith(position: position, isCompleted: false);
    _positionController.add(position);
    _stateController.add(_state);
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
