import 'dart:async';

import 'package:audio_service/audio_service.dart' as system_audio;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/system_media_controls_handler.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late _FakePlaybackSession session;
  late _FakeAudioPlayer audio;
  late SystemMediaControlsHandler handler;

  setUp(() {
    session = _FakePlaybackSession(
      PlaybackSessionState(
        queue: [_item('a', 'First'), _item('b', 'Second')],
        currentIndex: 0,
      ),
    );
    audio = _FakeAudioPlayer(
      const PlaybackState(
        isPlaying: true,
        isBuffering: false,
        isCompleted: false,
        isLoading: false,
        position: Duration(seconds: 12),
        duration: Duration(minutes: 3),
        bufferedPosition: Duration(seconds: 40),
        speed: 1,
        volume: 1,
        currentSource: AudioSourceType.original,
      ),
    );
    handler = SystemMediaControlsHandler(
      session: session,
      audioPlayer: audio,
    );
  });

  tearDown(() async {
    await handler.disposeBridge();
    await session.dispose();
    await audio.dispose();
  });

  test('publishes queue metadata and current playback state', () {
    expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
    expect(handler.mediaItem.value?.title, 'First');
    expect(handler.mediaItem.value?.artist, 'Artist');
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));

    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.queueIndex, 0);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.controls, contains(system_audio.MediaControl.pause));
    expect(state.controls, contains(system_audio.MediaControl.skipToNext));
  });

  test('system transport actions forward into app services', () async {
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.skipToQueueItem(1);
    await handler.seek(const Duration(seconds: 27));
    await handler.pause();
    await handler.play();

    expect(session.nextCalls, 1);
    expect(session.previousCalls, 1);
    expect(session.playAtCalls, [1]);
    expect(session.seekCalls, [const Duration(seconds: 27)]);
    expect(audio.pauseCalls, 1);
    expect(audio.playCalls, 1);
  });

  test('system shuffle and repeat use the existing app semantics', () async {
    await handler.setShuffleMode(system_audio.AudioServiceShuffleMode.all);
    await handler.setRepeatMode(system_audio.AudioServiceRepeatMode.one);

    expect(session.shuffleEnabled, isTrue);
    expect(session.repeatMode, PlaybackRepeatMode.one);

    await handler.setShuffleMode(system_audio.AudioServiceShuffleMode.none);
    await handler.setRepeatMode(system_audio.AudioServiceRepeatMode.none);

    expect(session.shuffleEnabled, isFalse);
    expect(session.repeatMode, PlaybackRepeatMode.off);
  });

  test('session changes refresh system queue and current item', () async {
    session.emit(
      PlaybackSessionState(
        queue: [_item('a', 'First'), _item('b', 'Second')],
        currentIndex: 1,
        shuffleEnabled: true,
        repeatMode: PlaybackRepeatMode.all,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handler.mediaItem.value?.title, 'Second');
    expect(handler.playbackState.value.queueIndex, 1);
    expect(
      handler.playbackState.value.shuffleMode,
      system_audio.AudioServiceShuffleMode.all,
    );
    expect(
      handler.playbackState.value.repeatMode,
      system_audio.AudioServiceRepeatMode.all,
    );
  });
}

PlaybackItem _item(String id, String title) => PlaybackItem(
      id: id,
      title: title,
      artist: 'Artist',
      artworkPath: '/tmp/$id.jpg',
      audioAsset: AudioAsset(
        originalPath: '/tmp/$id.mp3',
        format: 'mp3',
        duration: const Duration(minutes: 3),
        metadata: const {'album': 'Album'},
      ),
    );

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _controller =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state;

  int nextCalls = 0;
  int previousCalls = 0;
  final List<int> playAtCalls = [];
  final List<Duration> seekCalls = [];
  bool shuffleEnabled = false;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.off;

  _FakePlaybackSession(this._state);

  void emit(PlaybackSessionState value) {
    _state = value;
    _controller.add(value);
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  Future<void> skipNext() async => nextCalls++;

  @override
  Future<void> skipPrevious() async => previousCalls++;

  @override
  Future<void> playAt(int index) async => playAtCalls.add(index);

  @override
  Future<void> seek(Duration position) async => seekCalls.add(position);

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    shuffleEnabled = enabled;
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    repeatMode = mode;
  }

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
  Future<void> clearQueue({bool keepCurrent = true}) async {}

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> dispose() => _controller.close();
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _state;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  _FakeAudioPlayer(this._state);

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _state = const PlaybackState.idle();
    _stateController.add(_state);
  }

  @override
  Future<void> seek(Duration position) async {}

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
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() => _stateController.close();
}
