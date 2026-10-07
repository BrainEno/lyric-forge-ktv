import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/system_media_audio_handler.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart' as app;
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('remote stream publishes protected remote artwork before cache is ready', () async {
    final artwork = Uri.parse('http://127.0.0.1:48517/v1/tracks/a/artwork?token=secret');
    final item = _remoteItem(artwork: artwork);
    final session = _FakeSession(item);
    final audio = _FakeAudio();
    final handler = LyricForgeSystemMediaHandler(session: session, audio: audio);
    addTearDown(() async {
      await handler.disposeBridge();
      await session.dispose();
      await audio.dispose();
    });

    expect(handler.mediaItem.value?.artUri, artwork);
    expect(handler.queue.value.single.artUri, artwork);
  });

  test('cached local artwork takes precedence for remote system media', () async {
    final directory = await Directory.systemTemp.createTemp('elysium-lockscreen-art-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final cover = File('${directory.path}${Platform.pathSeparator}cover.png');
    await cover.writeAsBytes(const <int>[1, 2, 3, 4]);

    final artwork = Uri.parse('http://127.0.0.1:48517/v1/tracks/a/artwork?token=secret');
    final item = _remoteItem(artwork: artwork, localArtwork: cover.path);
    final session = _FakeSession(item);
    final audio = _FakeAudio();
    final handler = LyricForgeSystemMediaHandler(session: session, audio: audio);
    addTearDown(() async {
      await handler.disposeBridge();
      await session.dispose();
      await audio.dispose();
    });

    expect(handler.mediaItem.value?.artUri, Uri.file(cover.path));
  });
}

PlaybackItem _remoteItem({
  required Uri artwork,
  String? localArtwork,
}) {
  final stream = Uri.parse('http://127.0.0.1:48517/v1/tracks/a/audio?token=secret');
  return PlaybackItem(
    id: 'remote:desktop:a',
    title: 'Remote Song',
    artist: 'Remote Artist',
    artworkPath: localArtwork,
    streamUri: stream,
    audioAsset: AudioAsset(
      originalPath: stream.toString(),
      format: 'flac',
      duration: const Duration(minutes: 3),
      metadata: <String, dynamic>{
        'album': 'Remote Album',
        'remoteArtworkUri': artwork.toString(),
      },
    ),
  );
}

class _FakeSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _controller =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state;

  _FakeSession(PlaybackItem item)
      : _state = PlaybackSessionState(
          queue: <PlaybackItem>[item],
          currentIndex: 0,
        );

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  app.PlaybackState get playbackState => const app.PlaybackState.idle();

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {}

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {}

  @override
  Future<void> enqueue(PlaybackItem item) async {}

  @override
  Future<void> updateItem(PlaybackItem item) async {}

  @override
  Future<void> playAt(int index) async {}

  @override
  Future<void> removeAt(int index) async {}

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {}

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeAudio implements AudioPlayerService {
  final StreamController<app.PlaybackState> _stateController =
      StreamController<app.PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  final app.PlaybackState _state = app.PlaybackState(
    isPlaying: false,
    isBuffering: false,
    isCompleted: false,
    isLoading: false,
    position: Duration.zero,
    duration: const Duration(minutes: 3),
    bufferedPosition: Duration.zero,
    speed: 1,
    volume: 1,
  );

  @override
  app.PlaybackState get currentState => _state;

  @override
  Stream<app.PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

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
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}
