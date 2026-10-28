import '../models/transcription_models.dart';
import 'asr_runtime_manager.dart';
import 'batch_transcription_queue.dart';
import 'transcription_settings_store.dart';

class TranscriptionQueueEnvironmentRecoveryResult {
  final TranscriptionConfig config;
  final bool ready;
  final bool resumed;

  const TranscriptionQueueEnvironmentRecoveryResult({
    required this.config,
    required this.ready,
    required this.resumed,
  });
}

/// Closes the protective-pause recovery loop after a user finishes the ASR
/// setup dialog.
///
/// The queue is resumed only after the repaired configuration passes a fresh
/// runtime inspection and only if the queue is still paused for an environment
/// fault. A newer manual pause or other state change always wins.
class TranscriptionQueueEnvironmentRecovery {
  final TranscriptionSettingsStore settingsStore;
  final AsrRuntimeManager runtimeManager;
  final BatchTranscriptionQueue queue;

  const TranscriptionQueueEnvironmentRecovery({
    required this.settingsStore,
    required this.runtimeManager,
    required this.queue,
  });

  Future<TranscriptionQueueEnvironmentRecoveryResult> recover(
    TranscriptionConfig config,
  ) async {
    await settingsStore.save(config);
    final repaired = await runtimeManager.repair(config);
    final status = await runtimeManager.inspect(repaired);
    await settingsStore.save(repaired);

    if (!status.isReady) {
      return TranscriptionQueueEnvironmentRecoveryResult(
        config: repaired,
        ready: false,
        resumed: false,
      );
    }

    if (!queue.current.isEnvironmentBlocked) {
      return TranscriptionQueueEnvironmentRecoveryResult(
        config: repaired,
        ready: true,
        resumed: false,
      );
    }

    await queue.resume();
    return TranscriptionQueueEnvironmentRecoveryResult(
      config: repaired,
      ready: true,
      resumed: true,
    );
  }
}
