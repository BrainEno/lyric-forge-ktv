import 'dart:io';

import '../core/diagnostics/operation_timings.dart';
import '../features/player/data/services/local_ktv_recording_service.dart';
import '../features/player/data/services/timed_ktv_recording_service.dart';
import '../features/player/domain/services/audio_player_service.dart';
import '../features/player/domain/services/ktv_microphone_service.dart';
import '../features/player/domain/services/ktv_recording_service.dart';
import '../features/transcription/domain/services/transcription_settings_store.dart';

/// Connects KTV export to the shared user-selected FFmpeg setting without
/// making the player feature depend on transcription's settings model.
///
/// With [timings], recording start/stop and mix export are measured for the
/// diagnostics report (#226); behaviour and errors are unchanged.
KtvRecordingService assembleKtvRecordingService({
  required AudioPlayerService audioService,
  required KtvMicrophoneService microphoneService,
  required TranscriptionSettingsStore settingsStore,
  Future<ProcessResult> Function(String, List<String>)? processRunner,
  OperationTimings? timings,
}) {
  final service = LocalKtvRecordingService(
    audioService: audioService,
    microphoneService: microphoneService,
    loadFfmpegExecutable: () async =>
        (await settingsStore.load())?.ffmpegExecutable,
    processRunner: processRunner,
  );
  if (timings == null) return service;
  return TimedKtvRecordingService(
    delegate: service,
    timings: timings,
    microphone: microphoneService,
  );
}
