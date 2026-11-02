import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/exclusive_audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/audio_preview_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late List<String> log;
  late _FakePrimaryPlayer primary;
  late _FakePreviewService preview;
  late ExclusiveAudioPreviewService service;

  setUp(() {
    log = <String>[];
    primary = _FakePrimaryPlayer(log);
    preview = _FakePreviewService(log);
    service = ExclusiveAudioPreviewService(
      delegate: preview,
      primaryPlayer: primary,
    );
  });

  tearDown(() async {
    await service.dispose();
    await primary.dispose();
  });

  test('开始试听前先暂停正在播放的歌曲', () async {
    primary.emit(const PlaybackState.idle().copyWith(isPlaying: true));

    await service.play();

    expect(log, <String>['song.pause', 'preview.play']);
  });

  test('歌曲已经暂停时不重复发送暂停', () async {
    await service.play();

    expect(log, <String>['preview.play']);
  });

  test('歌曲重新开始播放时暂停试听', () async {
    preview.emit(const AudioPreviewState.idle().copyWith(isPlaying: true));

    primary.emit(const PlaybackState.idle().copyWith(isPlaying: true));
    await pumpEventQueue();

    expect(log, contains('preview.pause'));
  });

  test('歌曲的暂停事件不会打断试听', () async {
    preview.emit(const AudioPreviewState.idle().copyWith(isPlaying: true));

    primary.emit(const PlaybackState.idle());
    await pumpEventQueue();

    expect(log, isNot(contains('preview.pause')));
  });

  test('歌曲开始播放但试听本来就没在响时不做多余动作', () async {
    primary.emit(const PlaybackState.idle().copyWith(isPlaying: true));
    await pumpEventQueue();

    expect(log, isNot(contains('preview.pause')));
  });

  test('释放之后不再响应歌曲状态', () async {
    preview.emit(const AudioPreviewState.idle().copyWith(isPlaying: true));
    await service.dispose();
    // tearDown disposes again; make that harmless.

    primary.emit(const PlaybackState.idle().copyWith(isPlaying: true));
    await pumpEventQueue();

    expect(log, isNot(contains('preview.pause')));
  });
}

class _FakePreviewService implements AudioPreviewService {
  _FakePreviewService(this.log);

  final List<String> log;
  final StreamController<AudioPreviewState> _controller =
      StreamController<AudioPreviewState>.broadcast();
  AudioPreviewState _state = const AudioPreviewState.idle();

  void emit(AudioPreviewState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  AudioPreviewState get currentState => _state;

  @override
  Stream<AudioPreviewState> get stateStream => _controller.stream;

  @override
  Future<Duration?> loadFile(String path) async {
    log.add('preview.load:$path');
    return null;
  }

  @override
  Future<void> play() async => log.add('preview.play');

  @override
  Future<void> pause() async => log.add('preview.pause');

  @override
  Future<void> stop() async => log.add('preview.stop');

  @override
  Future<void> seek(Duration position) async =>
      log.add('preview.seek:${position.inMilliseconds}');

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

class _FakePrimaryPlayer implements AudioPlayerService {
  _FakePrimaryPlayer(this.log);

  final List<String> log;
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();

  void emit(PlaybackState state) {
    _state = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get stateStream => _controller.stream;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Future<void> play() async => log.add('song.play');

  @override
  Future<void> pause() async {
    log.add('song.pause');
    emit(_state.copyWith(isPlaying: false));
  }

  @override
  Future<void> stop() async => log.add('song.stop');

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}

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
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
