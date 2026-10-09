import 'dart:async';
import 'dart:math' as math;

import 'package:audio_io/audio_io.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/services/ktv_microphone_service.dart';
import 'pcm_delay_line.dart';

class AudioIoKtvMicrophoneService implements KtvMicrophoneService {
  static const int _sampleRate = 48000;

  final AudioIo _audioIo;
  final StreamController<KtvMicrophoneState> _stateController =
      StreamController<KtvMicrophoneState>.broadcast();
  final Stopwatch _levelClock = Stopwatch()..start();
  late final PcmDelayLine _delayLine;
  StreamSubscription<List<double>>? _inputSubscription;
  KtvMicrophoneState _state = const KtvMicrophoneState();
  int _lastLevelUpdateMs = 0;

  AudioIoKtvMicrophoneService({AudioIo? audioIo})
      : _audioIo = audioIo ?? AudioIo.instance {
    _delayLine = PcmDelayLine(
      sampleRate: _sampleRate,
      gain: _state.micGain,
      delay: _state.monitorDelay,
    );
  }

  @override
  Stream<KtvMicrophoneState> get stateStream => _stateController.stream;

  @override
  KtvMicrophoneState get currentState => _state;

  @override
  Future<void> startMonitoring() async {
    if (_state.isMonitoring || _state.isStarting) return;

    _emit(
      _state.copyWith(
        isStarting: true,
        permissionDenied: false,
        clearError: true,
      ),
    );

    try {
      if (!await _requestMicrophonePermissionIfNeeded()) {
        _emit(
          _state.copyWith(
            isStarting: false,
            isMonitoring: false,
            permissionDenied: true,
            error: '没有麦克风权限。请在系统设置中允许 Elysium Player 使用麦克风。',
          ),
        );
        return;
      }

      await _audioIo.startWith(
        const AudioIoConfig(
          sampleRate: AudioIoSampleRate.rate48000,
          format: AudioIoFormat.float64,
          latency: AudioIoLatency.Realtime,
          threading: AudioIoThreading.audioIsolate,
          outputBufferDuration: 0.08,
        ),
      );

      _inputSubscription = _audioIo.input.listen(
        _handleInputFrame,
        onError: _handleInputError,
      );

      Duration? engineLatency;
      try {
        final seconds = await _audioIo.currentLatency();
        if (seconds.isFinite && seconds >= 0) {
          engineLatency = Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond).round(),
          );
        }
      } catch (_) {
        // Some devices cannot report a stable hardware latency. Monitoring can
        // still continue, so this is intentionally non-fatal.
      }

      _emit(
        _state.copyWith(
          isStarting: false,
          isMonitoring: true,
          permissionDenied: false,
          engineLatency: engineLatency,
          clearEngineLatency: engineLatency == null,
          clearError: true,
        ),
      );
    } on AudioIoException catch (error) {
      await _stopEngineSilently();
      _emit(
        _state.copyWith(
          isStarting: false,
          isMonitoring: false,
          permissionDenied: error.isPermissionDenied,
          inputLevel: 0,
          clearEngineLatency: true,
          error: error.isPermissionDenied
              ? '麦克风权限被拒绝。请在系统设置中开启后重试。'
              : '无法启动麦克风监听：${error.message}',
        ),
      );
    } catch (error) {
      await _stopEngineSilently();
      _emit(
        _state.copyWith(
          isStarting: false,
          isMonitoring: false,
          inputLevel: 0,
          clearEngineLatency: true,
          error: '无法启动麦克风监听：$error',
        ),
      );
    }
  }

  @override
  Future<void> stopMonitoring() async {
    await _stopEngineSilently();
    _emit(
      _state.copyWith(
        isStarting: false,
        isMonitoring: false,
        inputLevel: 0,
        clearEngineLatency: true,
        clearError: true,
      ),
    );
  }

  @override
  Future<void> setMicGain(double gain) async {
    final normalized = clampKtvMicGain(gain);
    _delayLine.setGain(normalized);
    _emit(_state.copyWith(micGain: normalized));
  }

  @override
  Future<void> setMonitorDelay(Duration delay) async {
    final normalized = clampKtvMonitorDelay(delay);
    _delayLine.setDelay(normalized);
    if (_state.isMonitoring) {
      try {
        await _audioIo.clearOutput();
      } catch (_) {
        // The delay line itself is already reset; failure to clear a few queued
        // device frames should not break the live microphone session.
      }
    }
    _emit(_state.copyWith(monitorDelay: normalized));
  }

  void _handleInputFrame(List<double> samples) {
    if (!_state.isMonitoring || samples.isEmpty) return;

    final monitored = _delayLine.process(samples);
    _audioIo.output.add(monitored);

    final nowMs = _levelClock.elapsedMilliseconds;
    if (nowMs - _lastLevelUpdateMs < 50) return;
    _lastLevelUpdateMs = nowMs;

    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / samples.length).clamp(0.0, 1.0);
    _emit(_state.copyWith(inputLevel: rms.toDouble()));
  }

  void _handleInputError(Object error, StackTrace stackTrace) {
    if (!_state.isMonitoring && !_state.isStarting) return;
    unawaited(_recoverFromStreamError(error));
  }

  Future<void> _recoverFromStreamError(Object error) async {
    await _stopEngineSilently();
    _emit(
      _state.copyWith(
        isStarting: false,
        isMonitoring: false,
        inputLevel: 0,
        clearEngineLatency: true,
        error: '麦克风输入已中断：$error',
      ),
    );
  }

  Future<bool> _requestMicrophonePermissionIfNeeded() async {
    if (kIsWeb) return true;
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS &&
        platform != TargetPlatform.macOS) {
      return true;
    }

    final status = await Permission.microphone.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _stopEngineSilently() async {
    final subscription = _inputSubscription;
    _inputSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    try {
      await _audioIo.clearOutput();
    } catch (_) {}
    try {
      await _audioIo.stop();
    } catch (_) {}
  }

  void _emit(KtvMicrophoneState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  @override
  Future<void> dispose() async {
    await _stopEngineSilently();
    _audioIo.dispose();
    await _stateController.close();
  }
}
