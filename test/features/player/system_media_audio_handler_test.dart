import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/system_media_audio_handler.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart' as app;
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late _FakePlaybackSession session;
  late _FakeAudioPlayer audio;
  late LyricForgeSystemMediaHandler handler;

  setUp(() {
    final queue = [
      _item('one', '第一首', artist: '歌手 A', artworkPath: '/tmp/封面一.jpg'),
      _item('two', 'Second', artist: 'Artist B'),
    ];
    session = _FakePlaybackSession(
      PlaybackSessionState(queue: queue, currentIndex: 0),
    );
    audio = _FakeAudioPlayer(
      app.PlaybackState(
        isPlaying: false,
        isBuffering: false,
        isCompleted: false,
        isLoading: false,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 3),
        bufferedPosition: const Duration(seconds: 30),
        speed: 1,
        volume: 1,
      ),
    );
    handler = LyricForgeSystemMediaHandler(session: session, audio: audio);
  });

  tearDown(() async {
    await handler.disposeBridge();
    await session.dispose();
    await audio.dispose();
  });

  test('publishes queue, current metadata and platform controls', () {
    expect(handler.queue.value.map((item) => item.id), ['one', 'two']);
    expect(handler.mediaItem.value?.title, '第一首');
    expect(handler.mediaItem.value?.artist, '歌手 A');
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/封面一.jpg'));

    final state = handler.playbackState.value;
    expect(state.queueIndex, 0);
    expect(state.playing, isFalse);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.controls, contains(MediaControl.play));
    expect(state.controls, contains(MediaControl.skipToPrevious));
    expect(state.controls, contains(MediaControl.skipToNext));
  });

  test('system play and pause use the existing playback session', () async {
    await handler.play();
    expect(session.toggleCalls, 1);

    audio.emit(audio.currentState.copyWith(isPlaying: true));
    await Future<void>.delayed(Duration.zero);
    await handler.play();
    expect(session.toggleCalls, 1, reason: 'play must not toggle an already playing session');

    await handler.pause();
    expect(session.toggleCalls, 2);
  });

  test('headset next/previous and seek route through playback session', () async {
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 45));

    expect(session.nextCalls, 1);
    expect(session.previousCalls, 1);
    expect(session.lastSeek, const Duration(seconds: 45));
  });

  test('repeat and shuffle controls remain one shared state', () async {
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    await handler.setShuffleMode(AudioServiceShuffleMode.all);

    expect(session.lastRepeatMode, PlaybackRepeatMode.one);
    expect(session.lastShuffleEnabled, isTrue);

    session.emit(
      session.currentState.copyWith(
        repeatMode: PlaybackRepeatMode.all,
        shuffleEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
    expect(handler.playbackState.value.shuffleMode, AudioServiceShuffleMode.all);
  });

  test('session item change updates lock-screen media item and queue index', () async {
    session.emit(session.currentState.copyWith(currentIndex: 1));
    await Future<void>.delayed(Duration.zero);

    expect(handler.mediaItem.value?.id, 'two');
    expect(handler.mediaItem.value?.title, 'Second');
    expect(handler.playbackState.value.queueIndex, 1);
  });

  test('stop clears the shared queue rather than creating a second stop state', () async {
    await handler.stop();
    expect(session.clearQueueCalls, 1);
    expect(session.lastClearKeepCurrent, isFalse);
  });
}

PlaybackItem _item(
  String id,
  String title, {
  String? artist,
  String? artworkPath,
}) {
  return PlaybackItem(
    id: id,
    title: title,
    artist: artist,
    artworkPath: artworkPath,
    audioAsset: AudioAsset(
      originalPath: '/tmp/$id.mp3',
      format: 'mp3',
      duration: const Duration(minutes: 3),
      metadata: const {'album': '测试专辑'},
    ),
  );
}

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _controller =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state;

  int toggleCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int clearQueueCalls = 0;
  bool? lastClearKeepCurrent;
  Duration? lastSeek;
  PlaybackRepeatMode? lastRepeatMode;
  bool? lastShuffleEnabled;

  _FakePlaybackSession(this._state);

  void emit(PlaybackSessionState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  app.PlaybackState get playbackState => const app.PlaybackState.idle();

  @override
  Future<void> togglePlayPause() async {
    toggleCalls++;
  }

  @override
  Future<void> skipNext() async {
    nextCalls++;
  }

  @override
  Future<void> skipPrevious() async {
    previousCalls++;
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    lastRepeatMode = mode;
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;
  }

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {
    clearQueueCalls++;
    lastClearKeepCurrent = keepCurrent;
  }

  @override
  Future<void> playAt(int index) async {}

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {}

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {}

  @override
  Future<void> enqueue(PlaybackItem item) async {}

  @override
  Future<void> updateItem(PlaybackItem item) async {}

  @override
  Future<void> removeAt(int index) async {}

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<app.PlaybackState> _stateController =
      StreamController<app.PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  app.PlaybackState _state;

  _FakeAudioPlayer(this._state);

  void emit(app.PlaybackState next) {
    _state = next;
    _stateController.add(next);
  }

  @override
  app.PlaybackState get currentState => _state;

  @override
  Stream<app.PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> setSpeed(double speed) async {
    _state = _state.copyWith(speed: speed);
  }

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}
