import '../../../project/domain/models/project_manifest.dart';
import '../models/ktv_recording_session.dart';

class KtvTakeHistoryScanResult {
  final List<KtvRecordingSession> takes;
  final int recoveredCount;

  const KtvTakeHistoryScanResult({
    required this.takes,
    required this.recoveredCount,
  });
}

/// Project-level contract for discovering and managing completed KTV takes.
///
/// Directory-based entry points remain on the file-system implementation;
/// this contract intentionally exposes only project/domain types to callers.
abstract class KtvTakeHistoryStore {
  static const int maxDisplayNameLength = 80;

  Future<KtvTakeHistoryScanResult> scanProject(ProjectManifest project);

  Future<List<KtvRecordingSession>> listProject(ProjectManifest project);

  Future<KtvRecordingSession> updateProjectTakeMetadata(
    ProjectManifest project,
    KtvRecordingSession take, {
    String? displayName,
    bool clearDisplayName = false,
    bool? isFavorite,
  });

  Future<void> deleteProjectTake(
    ProjectManifest project,
    KtvRecordingSession take,
  );
}
