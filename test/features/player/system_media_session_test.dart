import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/system_media_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart'
    as app_state;
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late _FakeAudioPlayer audio;
  late _FakePlaybackSession session;
  late PlaybackSessionAudioHandler handler;

  setUp(() {
    audio = _FakeAudioPlayer();
    session = _FakePlaybackSession(audio);
    session.emit(
      PlaybackSessionState(
        queue: [_item('a', 'Song A'), _item('b', 'Song B')],
        currentIndex: 0,
      ),
    );
    audio.emit(
      const app_state.PlaybackState(
        isPlaying: true,
        isBuffering: false,
        isCompleted: false,
        isLoading: false,
        position: Duration(seconds: 12),
        duration: Duration(minutes: 3),
        bufferedPosition: Duration(seconds: 30),
        speed: 1,
        volume: 1,
      ),
    );
    handler = PlaybackSessionAudioHandler(
      playbackSession: session,
      audioPlayer: audio,
    );
  });

  tearDown(() async {
    await handler.disposeBridge();
    await audio.dispose();
    await session.dispose();
  });

  test('publishes LyricForge queue, current item and playback state', () {
    expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
    expect(handler.mediaItem.value?.id, 'a');
    expect(handler.mediaItem.value?.title, 'Song A');
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));

    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.queueIndex, 0);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.controls, contains(audio_service.MediaControl.pause));
    expect(state.controls, contains(audio_service.MediaControl.skipToNext));
  });

  test('system transport commands delegate to playback session', () async {
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 42));
    await handler.skipToQueueItem(1);
    await handler.pause();
    await handler.play();

    expect(session.nextCalls, 1);
    expect(session.previousCalls, 1);
    expect(session.lastSeek, const Duration(seconds: 42));
    expect(session.lastPlayAt, 1);
    expect(session.toggleCalls, 2);
  });

  test('completed track exposes replay and seeks to zero from system play', () async {
    audio.emit(
      const app_state.PlaybackState(
        isPlaying: true,
        isBuffering: false,
        isCompleted: true,
        isLoading: false,
        position: Duration(minutes: 3),
        duration: Duration(minutes: 3),
        bufferedPosition: Duration(minutes: 3),
        speed: 1,
        volume: 1,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.controls,
      contains(audio_service.MediaControl.play),
    );

    await handler.play();
    expect(session.lastSeek, Duration.zero);
    expect(session.toggleCalls, 0);
  });

  test('system repeat and shuffle modes update LyricForge session', () async {
    await handler.setRepeatMode(audio_service.AudioServiceRepeatMode.one);
    await handler.setShuffleMode(audio_service.AudioServiceShuffleMode.all);

    expect(session.lastRepeatMode, PlaybackRepeatMode.one);
    expect(session.lastShuffleEnabled, isTrue);
  });

  test('session mode changes are reflected back to system state', () async {
    session.emit(
      PlaybackSessionState(
        queue: [_item('a', 'Song A'), _item('b', 'Song B')],
        currentIndex: 1,
        repeatMode: PlaybackRepeatMode.all,
        shuffleEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final state = handler.playbackState.value;
    expect(state.queueIndex, 1);
    expect(state.repeatMode, audio_service.AudioServiceRepeatMode.all);
    expect(state.shuffleMode, audio_service.AudioServiceShuffleMode.all);
    expect(handler.mediaItem.value?.id, 'b');
  });

  test('empty queue exposes no invalid system play control', () async {
    session.emit(const PlaybackSessionState());
    await Future<void>.delayed(Duration.zero);

    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.controls, isEmpty);
    expect(
      handler.playbackState.value.processingState,
      audio_service.AudioProcessingState.idle,
    );
  });
}

PlaybackItem _item(String id, String title) {
  return PlaybackItem(
    id: id,
    title: title,
    artist: 'Artist',
    audioAsset: AudioAsset(
      originalPath: '/music/$id.mp3',
      format: 'mp3',
      duration: const Duration(minutes: 2),
    ),
  );
}

class _FakeAudioPlayer implements AudioPlayerService {
  final _stateController = StreamController<app_state.PlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  app_state.PlaybackState _state = const app_state.PlaybackState.idle();
  double? lastSpeed;

  void emit(app_state.PlaybackState state) {
    _state = state;
    _stateController.add(state);
    _positionController.add(state.position);
    _durationController.add(state.duration);
  }

  @override
  app_state.PlaybackState get currentState => _state;

  @override
  Stream<app_state.PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> setSpeed(double speed) async => lastSpeed = speed;

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> switchSource(AudioSourceType source) async {}
  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}
  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

class _FakePlaybackSession implements PlaybackSessionService {
  final _stateController = StreamController<PlaybackSessionState>.broadcast();
  final _FakeAudioPlayer audio;
  PlaybackSessionState _state = const PlaybackSessionState();
  int nextCalls = 0;
  int previousCalls = 0;
  int toggleCalls = 0;
  Duration? lastSeek;
  int? lastPlayAt;
  PlaybackRepeatMode? lastRepeatMode;
  bool? lastShuffleEnabled;

  _FakePlaybackSession(this.audio);

  void emit(PlaybackSessionState state) {
    _state = state;
    _stateController.add(state);
  }

  @override
  PlaybackSessionState get currentState => _state;

  @override
  Stream<PlaybackSessionState> get stateStream => _stateController.stream;

  @override
  app_state.PlaybackState get playbackState => audio.currentState;

  @override
  Future<void> skipNext() async => nextCalls++;

  @override
  Future<void> skipPrevious() async => previousCalls++;

  @override
  Future<void> seek(Duration position) async => lastSeek = position;

  @override
  Future<void> playAt(int index) async => lastPlayAt = index;

  @override
  Future<void> togglePlayPause() async {
    toggleCalls++;
    audio.emit(audio.currentState.copyWith(isPlaying: !audio.currentState.isPlaying));
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    lastRepeatMode = mode;
    emit(_state.copyWith(repeatMode: mode));
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;
    emit(_state.copyWith(shuffleEnabled: enabled));
  }

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {}
  @override
  Future<void> enqueue(PlaybackItem item) async {}
  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {}
  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {}
  @override
  Future<void> removeAt(int index) async {}
  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {}
  @override
  Future<void> updateItem(PlaybackItem item) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}
