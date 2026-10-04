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
  late SystemMediaAudioHandler handler;

  setUp(() {
    session = _FakePlaybackSession();
    audio = _FakeAudioPlayer();
    handler = SystemMediaAudioHandler(session: session, audio: audio);
  });

  tearDown(() async {
    await handler.close();
    await session.dispose();
    await audio.dispose();
  });

  test('publishes LyricForge queue and current media item metadata', () async {
    final first = _item('a', '第一首', artist: '艺人 A', artwork: '/tmp/a.jpg');
    final second = _item('b', 'Second');

    await session.setQueue([first, second]);
    await Future<void>.delayed(Duration.zero);

    expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
    expect(handler.mediaItem.value?.title, '第一首');
    expect(handler.mediaItem.value?.artist, '艺人 A');
    expect(handler.mediaItem.value?.artUri, Uri.file('/tmp/a.jpg'));
    expect(handler.playbackState.value.queueIndex, 0);
  });

  test('system transport controls delegate to shared playback session', () async {
    await session.setQueue([_item('a', 'A'), _item('b', 'B')]);

    await handler.play();
    expect(session.toggleCalls, 1);

    audio.emit(audio.currentState.copyWith(isPlaying: true));
    await handler.pause();
    expect(session.toggleCalls, 2);

    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 42));

    expect(session.nextCalls, 1);
    expect(session.previousCalls, 1);
    expect(session.lastSeek, const Duration(seconds: 42));
  });

  test('completed track exposes play and replays from zero', () async {
    await session.setQueue([_item('a', 'A')]);
    audio.emit(
      app.PlaybackState(
        isPlaying: true,
        isBuffering: false,
        isCompleted: true,
        isLoading: false,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 3),
        bufferedPosition: const Duration(minutes: 3),
        speed: 1.0,
        volume: 1.0,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handler.playbackState.value.controls, contains(MediaControl.play));
    expect(handler.playbackState.value.playing, isFalse);

    await handler.play();
    expect(session.lastSeek, Duration.zero);
  });

  test('next control follows queue boundary and repeat-all', () async {
    await session.setQueue([_item('a', 'A')]);
    await Future<void>.delayed(Duration.zero);
    expect(
      handler.playbackState.value.controls,
      isNot(contains(MediaControl.skipToNext)),
    );

    await session.setRepeatMode(PlaybackRepeatMode.all);
    await Future<void>.delayed(Duration.zero);
    expect(
      handler.playbackState.value.controls,
      contains(MediaControl.skipToNext),
    );
  });

  test('system queue selection, shuffle and repeat update app session', () async {
    await session.setQueue([
      _item('a', 'A'),
      _item('b', 'B'),
      _item('c', 'C'),
    ]);

    await handler.skipToQueueItem(2);
    expect(session.currentState.currentIndex, 2);

    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(session.currentState.shuffleEnabled, isTrue);

    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    expect(session.currentState.repeatMode, PlaybackRepeatMode.one);

    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(session.currentState.repeatMode, PlaybackRepeatMode.all);

    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    expect(session.currentState.shuffleEnabled, isFalse);
  });

  test('app playback state is reflected in OS playback state', () async {
    await session.setQueue([_item('a', 'A')]);
    audio.emit(
      app.PlaybackState(
        isPlaying: true,
        isBuffering: false,
        isCompleted: false,
        isLoading: false,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 3),
        bufferedPosition: const Duration(seconds: 30),
        speed: 1.0,
        volume: 1.0,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.bufferedPosition, const Duration(seconds: 30));
    expect(state.controls, contains(MediaControl.pause));
  });
}

PlaybackItem _item(
  String id,
  String title, {
  String? artist,
  String? artwork,
}) {
  return PlaybackItem(
    id: id,
    title: title,
    artist: artist,
    artworkPath: artwork,
    audioAsset: AudioAsset(
      originalPath: '/tmp/$id.mp3',
      format: 'mp3',
      duration: const Duration(minutes: 3),
    ),
  );
}

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _controller =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state = const PlaybackSessionState();

  int toggleCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  Duration? lastSeek;

  void _emit(PlaybackSessionState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  app.PlaybackState get playbackState => const app.PlaybackState.idle();

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    _emit(
      PlaybackSessionState(
        queue: List.unmodifiable(items),
        currentIndex: items.isEmpty ? -1 : startIndex,
        shuffleEnabled: _state.shuffleEnabled,
        repeatMode: _state.repeatMode,
      ),
    );
  }

  @override
  Future<void> playAt(int index) async {
    _emit(_state.copyWith(currentIndex: index));
  }

  @override
  Future<void> skipNext() async => nextCalls++;

  @override
  Future<void> skipPrevious() async => previousCalls++;

  @override
  Future<void> togglePlayPause() async => toggleCalls++;

  @override
  Future<void> seek(Duration position) async => lastSeek = position;

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    _emit(_state.copyWith(shuffleEnabled: enabled));
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _emit(_state.copyWith(repeatMode: mode));
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {}

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
  Future<void> dispose() => _controller.close();
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<app.PlaybackState> _state =
      StreamController<app.PlaybackState>.broadcast();
  app.PlaybackState _current = const app.PlaybackState.idle();

  void emit(app.PlaybackState state) {
    _current = state;
    _state.add(state);
  }

  @override
  app.PlaybackState get currentState => _current;

  @override
  Stream<app.PlaybackState> get stateStream => _state.stream;

  @override
  Stream<Duration> get positionStream =>
      _state.stream.map((state) => state.position);

  @override
  Stream<Duration?> get durationStream =>
      _state.stream.map((state) => state.duration);

  @override
  Future<void> pause() async {
    emit(_current.copyWith(isPlaying: false));
  }

  @override
  Future<void> play() async {
    emit(_current.copyWith(isPlaying: true, isCompleted: false));
  }

  @override
  Future<void> stop() async {
    emit(const app.PlaybackState.idle());
  }

  @override
  Future<void> seek(Duration position) async {
    emit(_current.copyWith(position: position, isCompleted: false));
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
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> setSpeed(double speed) async {
    emit(_current.copyWith(speed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    emit(_current.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() => _state.close();
}
