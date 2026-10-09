import '../../../project/domain/models/project_manifest.dart';
import '../models/ktv_recording_session.dart';

abstract class KtvRecordingService {
  Stream<KtvRecordingState> get stateStream;
  KtvRecordingState get currentState;

  Future<void> startRecording(ProjectManifest project);
  Future<KtvRecordingSession?> stopRecording();

  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  });

  Future<List<KtvRecordingSession>> listRecordings(ProjectManifest project);

  Future<void> deleteRecording(KtvRecordingSession session);

  Future<void> dispose();
}
