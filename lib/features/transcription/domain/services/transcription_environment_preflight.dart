import '../models/transcription_models.dart';
import 'asr_runtime_manager.dart';
import 'transcription_settings_store.dart';

enum TranscriptionEnvironmentReadinessState {
  unconfigured,
  ready,
  needsSetup,
  failed,
}

class TranscriptionEnvironmentReadiness {
  final TranscriptionEnvironmentReadinessState state;
  final TranscriptionConfig? config;
  final AsrRuntimeStatus? status;
  final String? error;

  const TranscriptionEnvironmentReadiness({
    required this.state,
    this.config,
    this.status,
    this.error,
  });

  bool get isReady => state == TranscriptionEnvironmentReadinessState.ready;

  bool get isConfigured => config != null;

  List<AsrRuntimeComponentStatus> get blockingComponents {
    final components = status?.components;
    if (components == null) return const <AsrRuntimeComponentStatus>[];
    return components
        .where(
          (component) =>
              component.state != AsrRuntimeComponentState.ready,
        )
        .toList(growable: false);
  }
}

/// Performs the same runtime readiness check used immediately before local ASR,
/// but without starting a project or mutating the background queue.
///
/// This gives import/onboarding surfaces a cheap gate so users can prepare the
/// local runtime before adding many songs and avoids a batch of predictable
/// environment failures. The queue still keeps its own environment-block guard
/// as a final safety net for restored jobs and non-UI callers.
class TranscriptionEnvironmentPreflight {
  final TranscriptionSettingsStore settingsStore;
  final AsrRuntimeManager runtimeManager;

  const TranscriptionEnvironmentPreflight({
    required this.settingsStore,
    required this.runtimeManager,
  });

  Future<TranscriptionEnvironmentReadiness> inspect() async {
    final current = await settingsStore.load();
    if (current == null) {
      return const TranscriptionEnvironmentReadiness(
        state: TranscriptionEnvironmentReadinessState.unconfigured,
      );
    }

    try {
      final repaired = await runtimeManager.repair(current);
      // Persist auto-resolved managed paths so every entry point and the next
      // transcription run sees exactly the configuration that was inspected.
      await settingsStore.save(repaired);
      final status = await runtimeManager.inspect(repaired);
      return TranscriptionEnvironmentReadiness(
        state: status.isReady
            ? TranscriptionEnvironmentReadinessState.ready
            : TranscriptionEnvironmentReadinessState.needsSetup,
        config: repaired,
        status: status,
      );
    } catch (error) {
      return TranscriptionEnvironmentReadiness(
        state: TranscriptionEnvironmentReadinessState.failed,
        config: current,
        error: error.toString(),
      );
    }
  }
}
