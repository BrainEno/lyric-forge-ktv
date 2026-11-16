import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/diagnostics/operation_timings.dart';
import '../../../../core/diagnostics/process_memory.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/services/ktv_microphone_service.dart';
import '../../domain/services/ktv_recording_service.dart';

/// Measures KTV recording on the real device without changing behaviour.
///
/// - `ktv.startRecording`: time from the tap to recording, i.e. the wait
///   before the backing track starts.
/// - `ktv.stopRecording`: finishing the take; the sample carries the take
///   length.
/// - `ktv.exportMix`: FFmpeg mixdown; its real-time factor is the long-song
///   processing benchmark issue #226 asks for.
///
/// The microphone engine's reported latency and the monitor delay are
/// attached to the start sample when available, so a report shows what the
/// device claimed alongside what the user experienced.
class TimedKtvRecordingService implements KtvRecordingService {
  TimedKtvRecordingService({
    required KtvRecordingService delegate,
    required OperationTimings timings,
    KtvMicrophoneService? microphone,
    AppLogger? logger,
    Map<String, Object?> Function()? memoryProbe,
  }) : _delegate = delegate,
       _timings = timings,
       _microphone = microphone,
       _logger = logger ?? appLog,
       _memoryProbe = memoryProbe ?? processMemoryAttributes;

  static const String startOperation = 'ktv.startRecording';
  static const String stopOperation = 'ktv.stopRecording';
  static const String exportOperation = 'ktv.exportMix';
  static const String logTag = 'ktv';

  final KtvRecordingService _delegate;
  final OperationTimings _timings;
  final KtvMicrophoneService? _microphone;
  final AppLogger _logger;
  final Map<String, Object?> Function() _memoryProbe;

  @override
  Stream<KtvRecordingState> get stateStream => _delegate.stateStream;

  @override
  KtvRecordingState get currentState => _delegate.currentState;

  @override
  Future<void> startRecording(ProjectManifest project) async {
    final span = _timings.start(startOperation);
    try {
      await _delegate.startRecording(project);
    } catch (error, stackTrace) {
      span.finish(
        outcome: OperationOutcome.failure,
        attributes: {'error': '${error.runtimeType}'},
      );
      _logger.warning(
        logTag,
        'Recording did not start',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    span.finish(attributes: _microphoneAttributes());
  }

  @override
  Future<KtvRecordingSession?> stopRecording() async {
    final span = _timings.start(stopOperation);
    final KtvRecordingSession? session;
    try {
      session = await _delegate.stopRecording();
    } catch (error, stackTrace) {
      span.finish(
        outcome: OperationOutcome.failure,
        attributes: {'error': '${error.runtimeType}'},
      );
      _logger.warning(
        logTag,
        'Recording did not stop cleanly',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (session == null) {
      span.finish(
        outcome: OperationOutcome.cancelled,
        attributes: const {'session': false},
      );
      return null;
    }
    span.finish(
      mediaDuration: session.duration,
      attributes: {
        'alignmentReliable': session.alignmentReliable,
        'backingSource': session.backingSource.name,
      },
    );
    if (!session.alignmentReliable) {
      _logger.warning(
        logTag,
        'Take alignment is not reliable'
        '${session.alignmentIssue == null ? '' : ': ${session.alignmentIssue}'}',
      );
    }
    return session;
  }

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async {
    final span = _timings.start(exportOperation);
    try {
      final exported = await _delegate.exportMix(
        session,
        voiceVolume: voiceVolume,
        backingVolume: backingVolume,
      );
      span.finish(
        mediaDuration: session.duration,
        attributes: {
          'backingSource': session.backingSource.name,
          ..._memoryProbe(),
        },
      );
      return exported;
    } catch (error, stackTrace) {
      span.finish(
        outcome: OperationOutcome.failure,
        mediaDuration: session.duration,
        attributes: {'error': '${error.runtimeType}'},
      );
      _logger.warning(
        logTag,
        'Mix export failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() => _delegate.dispose();

  Map<String, Object?> _microphoneAttributes() {
    final microphone = _microphone;
    if (microphone == null) return const {};
    final state = microphone.currentState;
    return {
      'monitoring': state.isMonitoring,
      'monitorDelayMs': state.monitorDelay.inMilliseconds,
      if (state.engineLatency != null)
        'engineLatencyMs': state.engineLatency!.inMilliseconds,
    };
  }
}
