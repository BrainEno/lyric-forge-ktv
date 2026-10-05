import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';

/// just_audio 实现的音频播放器服务
class JustAudioPlayerService implements AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  AudioAsset? _currentAsset;
  AudioSourceType? _currentSource;

  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _currentState = const PlaybackState.idle();

  JustAudioPlayerService() {
    _initStateStreams();
  }

  void _initStateStreams() {
    _player.playerStateStream.listen((playerState) {
      _updateState();
    });

    _player.positionStream.listen((position) {
      _updateState();
    });

    _player.durationStream.listen((duration) {
      _updateState();
    });

    _player.bufferedPositionStream.listen((buffered) {
      _updateState();
    });
  }

  void _updateState() {
    final playerState = _player.playerState;
    final isLoading = playerState.processingState == ProcessingState.loading;
    final isBuffering = playerState.processingState == ProcessingState.buffering;
    final isCompleted = playerState.processingState == ProcessingState.completed;

    _currentState = PlaybackState(
      isPlaying: playerState.playing,
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      isLoading: isLoading,
      position: _player.position,
      duration: _player.duration,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      volume: _player.volume,
      currentSource: _currentSource,
      error: null,
    );

    _stateController.add(_currentState);
  }

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    _currentAsset = audioAsset;

    AudioSourceType source = preferredSource;
    if (!audioAsset.hasSource(source)) {
      source = audioAsset.defaultSource;
    }

    await _loadProjectSource(source);
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    if (uri.scheme != 'http' &&
        uri.scheme != 'https' &&
        uri.scheme != 'file') {
      throw ArgumentError.value(
        uri,
        'uri',
        '仅支持 http、https 或 file URI',
      );
    }

    _currentAsset = null;
    _currentSource = source;

    if (uri.scheme == 'file') {
      await _player.setFilePath(uri.toFilePath());
      return;
    }

    await _player.setUrl(uri.toString());
  }

  Future<void> _loadProjectSource(AudioSourceType source) async {
    if (_currentAsset == null) return;

    final path = _currentAsset!.getPathForSource(source);
    if (path == null) {
      throw Exception('Source $source not available');
    }

    _currentSource = source;
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await _player.setUrl(uri.toString());
      return;
    }
    if (uri != null && uri.scheme == 'file') {
      await _player.setFilePath(uri.toFilePath());
      return;
    }
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> switchSource(AudioSourceType source) async {
    if (_currentAsset == null) {
      throw StateError('当前播放项不是可切换音源的本地工程');
    }
    if (!_currentAsset!.hasSource(source)) {
      throw Exception('Source $source not available for this project');
    }

    final wasPlaying = _player.playing;
    final currentPosition = _player.position;

    await _loadProjectSource(source);
    await _player.seek(currentPosition);

    if (wasPlaying) {
      await _player.play();
    }
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  PlaybackState get currentState => _currentState;

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _player.dispose();
  }
}
