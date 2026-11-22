import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/project_audio_source_update.dart';
import 'desktop_audio_backend.dart';

/// just_audio 实现的音频播放器服务。
///
/// Windows/Linux 会在构造底层 AudioPlayer 前注册 media-kit/libmpv/FFmpeg
/// 后端，以兼容 VBR、较老 MPEG Layer III 变体以及宿主系统解码器不支持的
/// MP3 文件。移动端继续使用 just_audio 原生后端。
class JustAudioPlayerService
    implements AudioPlayerService, ActiveProjectAudioSourceUpdater {
  late final AudioPlayer _player;
  AudioAsset? _currentAsset;
  AudioSourceType? _currentSource;
  String? _lastError;
  int _loadsInFlight = 0;

  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _currentState = const PlaybackState.idle();

  JustAudioPlayerService() {
    initializeDesktopAudioBackend();
    _player = AudioPlayer();
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

    _player.errorStream.listen((error) {
      _lastError = _friendlyPlaybackError(error);
      _updateState();
    });
  }

  String _friendlyPlaybackError(Object error) {
    return '无法解码或播放此音频。文件可能损坏，或实际编码与扩展名不一致。'
        '桌面端已启用兼容解码后端。\n$error';
  }

  Future<void> _runLoad(Future<void> Function() operation) async {
    _lastError = null;
    _loadsInFlight++;
    try {
      await operation();
    } catch (error) {
      _lastError = _friendlyPlaybackError(error);
      _updateState();
      rethrow;
    } finally {
      _loadsInFlight--;
    }
  }

  @override
  bool updateActiveProjectAudioSources({
    required AudioAsset expected,
    required AudioAsset replacement,
  }) {
    if (_loadsInFlight > 0 || _lastError != null) return false;
    final next = safeProjectAudioSourceUpdate(
      current: _currentAsset,
      expected: expected,
      replacement: replacement,
      activeSource: _currentSource,
    );
    if (next == null) return false;
    _currentAsset = next;
    return true;
  }

  void _updateState() {
    if (_stateController.isClosed) return;

    final playerState = _player.playerState;
    final isLoading = playerState.processingState == ProcessingState.loading;
    final isBuffering =
        playerState.processingState == ProcessingState.buffering;
    final isCompleted =
        playerState.processingState == ProcessingState.completed;

    _currentState = PlaybackState(
      isPlaying: reportsPlaying(
        playing: playerState.playing,
        processingState: playerState.processingState,
      ),
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      isLoading: isLoading,
      position: _player.position,
      duration: _player.duration,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      volume: _player.volume,
      currentSource: _currentSource,
      error: _lastError,
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
    if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'file') {
      throw ArgumentError.value(uri, 'uri', '仅支持 http、https 或 file URI');
    }

    _currentAsset = null;
    _currentSource = source;

    if (uri.scheme == 'file') {
      await _runLoad(() async {
        await _player.setFilePath(uri.toFilePath());
      });
      return;
    }

    await _runLoad(() async {
      await _player.setUrl(uri.toString());
    });
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
      await _runLoad(() async {
        await _player.setUrl(uri.toString());
      });
      return;
    }
    if (uri != null && uri.scheme == 'file') {
      await _runLoad(() async {
        await _player.setFilePath(uri.toFilePath());
      });
      return;
    }
    await _runLoad(() async {
      await _player.setFilePath(path);
    });
  }

  /// Whether the app should call the song playing (D-059).
  ///
  /// just_audio keeps `playing` true after the last song ends: the player
  /// only stopped because there was nothing left. The rhythm bars, the
  /// turning record and the pause icon all read this flag, so a finished
  /// queue looked as if it was still playing.
  static bool reportsPlaying({
    required bool playing,
    required ProcessingState processingState,
  }) => playing && processingState != ProcessingState.completed;

  /// Waits for playback to start, not to end (D-059).
  ///
  /// just_audio's `play()` completes only when playback is paused or the
  /// song ends, so every `await play()` in the session — saving the play
  /// history, the library reloading after a tap — waited for the next pause.
  /// This completes once [states] report the player playing and ready, or
  /// as soon as [playback] itself completes or fails; a start failure still
  /// reaches the caller.
  static Future<void> untilStarted(
    Future<void> playback,
    Stream<PlayerState> states,
  ) {
    final started = states
        .firstWhere(
          (state) =>
              state.playing && state.processingState == ProcessingState.ready,
        )
        .then<void>((_) {});
    return Future.any<void>([playback, started]);
  }

  @override
  Future<void> play() async {
    try {
      // A finished song starts again from the top.
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await untilStarted(_player.play(), _player.playerStateStream);
    } catch (error) {
      _lastError = _friendlyPlaybackError(error);
      _updateState();
      rethrow;
    }
  }

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
      await play();
    }
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());
    _updateState();
  }

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
    await _player.dispose();
    await _stateController.close();
  }
}
