import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/services/ktv_microphone_service.dart';
import 'pcm_delay_line.dart';

/// Low-latency KTV microphone monitoring.
///
/// Microphone capture and monitor playback intentionally live outside the
/// regular song player. This keeps singer gain/latency independent from the
/// backing-track volume and prevents KTV monitoring from mutating playback
/// position or source selection.
class RecordSoloudKtvMicrophoneService implements KtvMicrophoneService {
  static const int _sampleRate = 48000;

  final AudioRecorder _recorder;
  final SoLoud _soloud;
  final StreamController<KtvMicrophoneState> _stateController =
      StreamController<KtvMicrophoneState>.broadcast();
  final StreamController<Uint8List> _rawPcmController =
      StreamController<Uint8List>.broadcast(sync: true);
  final Stopwatch _levelClock = Stopwatch()..start();
  final Map<String, InputDevice> _recordInputDevices = <String, InputDevice>{};
  late final PcmDelayLine _delayLine;

  StreamSubscription<Uint8List>? _inputSubscription;
  AudioSource? _monitorSource;
  SoundHandle? _monitorHandle;
  KtvMicrophoneState _state = const KtvMicrophoneState();
  int _lastLevelUpdateMs = 0;
  bool _initializedSoloud = false;

  RecordSoloudKtvMicrophoneService({AudioRecorder? recorder, SoLoud? soloud})
    : _recorder = recorder ?? AudioRecorder(),
      _soloud = soloud ?? SoLoud.instance {
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
  Stream<Uint8List> get rawPcm16Stream => _rawPcmController.stream;

  @override
  Future<void> refreshInputDevices() =>
      _refreshInputDevices(surfaceErrors: true);

  Future<void> _refreshInputDevices({required bool surfaceErrors}) async {
    if (_state.isRefreshingInputDevices) return;
    _emit(_state.copyWith(isRefreshingInputDevices: true));

    try {
      final devices = await _recorder.listInputDevices();
      _recordInputDevices
        ..clear()
        ..addEntries(
          devices
              .where((device) => device.id.trim().isNotEmpty)
              .map((device) => MapEntry(device.id, device)),
        );

      final mapped =
          _recordInputDevices.values
              .map(
                (device) => KtvAudioInputDevice(
                  id: device.id,
                  label: device.label.trim().isEmpty
                      ? '未命名输入设备'
                      : device.label.trim(),
                ),
              )
              .toList(growable: false)
            ..sort((left, right) => left.label.compareTo(right.label));
      final selectedId = _state.selectedInputDeviceId;
      final selectedStillAvailable =
          selectedId == null || _recordInputDevices.containsKey(selectedId);

      _emit(
        _state.copyWith(
          isRefreshingInputDevices: false,
          inputDevices: List<KtvAudioInputDevice>.unmodifiable(mapped),
          clearSelectedInputDevice: !selectedStillAvailable,
          clearError: true,
        ),
      );
    } catch (error) {
      _emit(
        _state.copyWith(
          isRefreshingInputDevices: false,
          error: surfaceErrors ? '无法读取麦克风设备列表：$error' : null,
          clearError: !surfaceErrors,
        ),
      );
    }
  }

  @override
  Future<void> selectInputDevice(String? deviceId) async {
    final normalizedId = deviceId?.trim();
    if (normalizedId != null && normalizedId.isNotEmpty) {
      if (!_recordInputDevices.containsKey(normalizedId)) {
        await _refreshInputDevices(surfaceErrors: false);
      }
      if (!_recordInputDevices.containsKey(normalizedId)) {
        _emit(_state.copyWith(error: '所选麦克风已不可用，请刷新设备列表后重试'));
        return;
      }
    }

    final nextId = normalizedId == null || normalizedId.isEmpty
        ? null
        : normalizedId;
    if (_state.selectedInputDeviceId == nextId) return;

    final restartMonitoring = _state.isMonitoring;
    if (restartMonitoring) {
      await _stopSessionSilently();
      _emit(
        _state.copyWith(
          isMonitoring: false,
          inputLevel: 0,
          clearEngineLatency: true,
        ),
      );
    }

    _emit(
      _state.copyWith(
        selectedInputDeviceId: nextId,
        clearSelectedInputDevice: nextId == null,
        clearError: true,
      ),
    );

    if (restartMonitoring) {
      await startMonitoring();
    }
  }

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
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
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

      await _refreshInputDevices(surfaceErrors: false);

      final pcmSupported = await _recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!pcmSupported) {
        throw StateError('当前设备不支持 PCM16 麦克风流');
      }

      if (!_soloud.isInitialized) {
        await _soloud.init(
          sampleRate: _sampleRate,
          bufferSize: 256,
          channels: Channels.stereo,
          lowLatency: true,
        );
        _initializedSoloud = true;
      }

      final monitorSource = _soloud.setBufferStream(
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0.02,
        maxBufferSizeDuration: const Duration(milliseconds: 250),
        sampleRate: _sampleRate,
        channels: Channels.mono,
        format: BufferType.s16le,
      );
      final monitorHandle = _soloud.play(monitorSource);
      final selectedDevice = _state.selectedInputDeviceId == null
          ? null
          : _recordInputDevices[_state.selectedInputDeviceId!];

      final input = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
          streamBufferSize: 2048,
          device: selectedDevice,
        ),
      );

      _monitorSource = monitorSource;
      _monitorHandle = monitorHandle;
      _inputSubscription = input.listen(
        _handleInputFrame,
        onError: _handleInputError,
      );

      final outputLatency = _soloud.getOutputLatency();
      _emit(
        _state.copyWith(
          isStarting: false,
          isMonitoring: true,
          permissionDenied: false,
          engineLatency: outputLatency > Duration.zero ? outputLatency : null,
          clearEngineLatency: outputLatency <= Duration.zero,
          clearError: true,
        ),
      );
    } catch (error) {
      await _stopSessionSilently();
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
    await _stopSessionSilently();
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
    _emit(_state.copyWith(monitorDelay: normalized));
  }

  void _handleInputFrame(Uint8List bytes) {
    if (!_state.isMonitoring || bytes.length < 2) return;
    if (!_rawPcmController.isClosed) {
      _rawPcmController.add(Uint8List.fromList(bytes));
    }

    final sampleCount = bytes.length ~/ 2;
    final data = ByteData.sublistView(bytes);
    final samples = List<double>.filled(sampleCount, 0, growable: false);
    var sumSquares = 0.0;

    for (var index = 0; index < sampleCount; index++) {
      final sample = data.getInt16(index * 2, Endian.little) / 32768.0;
      samples[index] = sample;
      sumSquares += sample * sample;
    }

    final monitored = _delayLine.process(samples);
    final output = Uint8List(monitored.length * 2);
    final outputData = ByteData.sublistView(output);
    for (var index = 0; index < monitored.length; index++) {
      final pcm = (monitored[index] * 32767.0).round().clamp(-32768, 32767);
      outputData.setInt16(index * 2, pcm, Endian.little);
    }

    final source = _monitorSource;
    if (source != null) {
      try {
        _soloud.addAudioDataStream(source, output);
      } catch (error) {
        _handleInputError(error, StackTrace.current);
        return;
      }
    }

    final nowMs = _levelClock.elapsedMilliseconds;
    if (nowMs - _lastLevelUpdateMs < 50) return;
    _lastLevelUpdateMs = nowMs;
    final rms = math.sqrt(sumSquares / sampleCount).clamp(0.0, 1.0);
    _emit(_state.copyWith(inputLevel: rms.toDouble()));
  }

  void _handleInputError(Object error, StackTrace stackTrace) {
    if (!_state.isMonitoring && !_state.isStarting) return;
    if (!_rawPcmController.isClosed) {
      _rawPcmController.addError(error, stackTrace);
    }
    unawaited(_recoverFromStreamError(error));
  }

  Future<void> _recoverFromStreamError(Object error) async {
    await _stopSessionSilently();
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

  Future<void> _stopSessionSilently() async {
    final subscription = _inputSubscription;
    _inputSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}

    final source = _monitorSource;
    final handle = _monitorHandle;
    _monitorSource = null;
    _monitorHandle = null;

    if (source != null) {
      try {
        _soloud.setDataIsEnded(source);
      } catch (_) {}
    }
    if (handle != null) {
      try {
        await _soloud.stop(handle);
      } catch (_) {}
    }
    if (source != null) {
      try {
        await _soloud.disposeSource(source);
      } catch (_) {}
    }
  }

  void _emit(KtvMicrophoneState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  @override
  Future<void> dispose() async {
    await _stopSessionSilently();
    await _recorder.dispose();
    if (_initializedSoloud && _soloud.isInitialized) {
      await _soloud.deinitAsync();
    }
    await _rawPcmController.close();
    await _stateController.close();
  }
}
