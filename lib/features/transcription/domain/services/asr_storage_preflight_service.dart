import '../models/transcription_models.dart';
import 'asr_runtime_manager.dart';

enum AsrStoragePreflightState {
  ready,
  sufficient,
  insufficient,
  unknown,
  notApplicable,
}

class AsrStoragePreflightResult {
  final AsrStoragePreflightState state;
  final String managedRoot;
  final int estimatedInstalledBytes;
  final int existingRelevantBytes;
  final int temporaryHeadroomBytes;
  final int safetyMarginBytes;
  final int requiredAdditionalBytes;
  final int? availableBytes;
  final String detail;

  const AsrStoragePreflightResult({
    required this.state,
    required this.managedRoot,
    required this.estimatedInstalledBytes,
    required this.existingRelevantBytes,
    required this.temporaryHeadroomBytes,
    required this.safetyMarginBytes,
    required this.requiredAdditionalBytes,
    required this.availableBytes,
    required this.detail,
  });

  bool get canInstall => state != AsrStoragePreflightState.insufficient;

  bool get hasKnownFreeSpace => availableBytes != null;

  int get shortfallBytes {
    final available = availableBytes;
    if (available == null || available >= requiredAdditionalBytes) return 0;
    return requiredAdditionalBytes - available;
  }
}

abstract class AsrStoragePreflightService {
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  });
}
