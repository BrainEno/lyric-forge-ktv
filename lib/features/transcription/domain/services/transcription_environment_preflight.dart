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

  /// Components that actually block recognition.
  ///
  /// A missing optional second engine is reported separately by the runtime
  /// panel; it degrades a run rather than preventing it.
  List<AsrRuntimeComponentStatus> get blockingComponents =>
      status?.missingBaselineComponents ?? const <AsrRuntimeComponentStatus>[];
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
        // The baseline is what decides whether lyrics can be produced at all.
        // A missing second engine only degrades the result, so gating import on
        // it would block precisely the setups that already work.
        state: status.isBaselineReady
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
