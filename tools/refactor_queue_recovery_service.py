from pathlib import Path

path = Path('lib/features/transcription/presentation/widgets/transcription_queue_panel.dart')
text = path.read_text(encoding='utf-8')
old_imports = "import '../../domain/models/transcription_models.dart';\nimport '../../domain/models/transcription_queue_models.dart';\nimport 'asr_runtime_setup_dialog.dart';\nimport '../../domain/services/batch_transcription_queue.dart';\n"
new_imports = "import '../../domain/models/transcription_models.dart';\nimport '../../domain/models/transcription_queue_models.dart';\nimport '../../domain/services/batch_transcription_queue.dart';\nimport '../../domain/services/transcription_queue_environment_recovery.dart';\nimport 'asr_runtime_setup_dialog.dart';\n"
if text.count(old_imports) != 1:
    raise RuntimeError('unexpected import block')
text = text.replace(old_imports, new_imports, 1)
old = '''    final services = ServiceLocatorGlobal.I;
    final store = services.transcriptionSettingsStore;
    final runtime = services.asrRuntimeManager;

    try {
      final current = await store.load();
      if (!context.mounted) return;

      final updated = await showDialog<TranscriptionConfig>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AsrRuntimeSetupDialog(initialConfig: current),
      );
      if (updated == null) return;

      await store.save(updated);
      final repaired = await runtime.repair(updated);
      final status = await runtime.inspect(repaired);
      await store.save(repaired);
      if (!context.mounted) return;

      if (!status.isReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('识别环境仍未完全就绪，队列继续保持暂停。'),
          ),
        );
        return;
      }

      // Resume only an environment-protective pause. If the queue state changed
      // while the repair dialog was open (for example the user manually paused
      // it elsewhere), never override that newer intent.
      if (!queue.current.isEnvironmentBlocked) return;
      await queue.resume();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('识别环境已恢复，后台队列已继续。'),
        ),
      );
'''
new = '''    final services = ServiceLocatorGlobal.I;
    final store = services.transcriptionSettingsStore;

    try {
      final current = await store.load();
      if (!context.mounted) return;

      final updated = await showDialog<TranscriptionConfig>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AsrRuntimeSetupDialog(initialConfig: current),
      );
      if (updated == null) return;

      final recovery = TranscriptionQueueEnvironmentRecovery(
        settingsStore: store,
        runtimeManager: services.asrRuntimeManager,
        queue: queue,
      );
      final result = await recovery.recover(updated);
      if (!context.mounted) return;

      if (!result.ready) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('识别环境仍未完全就绪，队列继续保持暂停。'),
          ),
        );
        return;
      }
      if (!result.resumed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('识别环境已恢复；队列状态已被其他操作改变，因此没有自动继续。'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('识别环境已恢复，后台队列已继续。'),
        ),
      );
'''
if text.count(old) != 1:
    raise RuntimeError('unexpected repair implementation')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
