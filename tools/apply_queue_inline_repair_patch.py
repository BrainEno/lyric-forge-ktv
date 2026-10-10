from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


panel = 'lib/features/transcription/presentation/widgets/transcription_queue_panel.dart'
replace_once(
    panel,
    "import '../../../../core/navigation/app_router.dart';\n",
    '',
)
replace_once(
    panel,
    "import '../../domain/models/transcription_queue_models.dart';\n",
    "import '../../domain/models/transcription_models.dart';\n"
    "import '../../domain/models/transcription_queue_models.dart';\n"
    "import 'asr_runtime_setup_dialog.dart';\n",
)
replace_once(
    panel,
    "                _EnvironmentBlockedCard(\n"
    "                  message: state.pauseMessage,\n"
    "                  onRepair: () => Navigator.pushNamed(context, Routes.settings),\n"
    "                ),",
    "                _EnvironmentBlockedCard(\n"
    "                  message: state.pauseMessage,\n"
    "                  onRepair: () => _repairEnvironment(context, service),\n"
    "                ),",
)
marker = "  TranscriptionQueueItem? _firstWithStatus(\n"
method = r'''  Future<void> _repairEnvironment(
    BuildContext context,
    BatchTranscriptionQueue queue,
  ) async {
    final services = ServiceLocatorGlobal.I;
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
    } on TranscriptionException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别环境仍需处理：$error')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查识别环境失败：$error')),
      );
    }
  }

'''
replace_once(panel, marker, method + marker)

# Update the protective-pause contract: repair is now closed-loop rather than a
# navigation detour to Settings.
test = 'test/features/transcription/transcription_queue_protective_pause_contract_test.dart'
replace_once(
    test,
    "    expect(panel, contains(\"Navigator.pushNamed(context, Routes.settings)\"));\n"
    "    expect(panel, contains('修复识别环境'));\n"
    "    expect(panel, contains('后续歌曲已保护性暂停'));",
    "    expect(panel, contains('AsrRuntimeSetupDialog(initialConfig: current)'));\n"
    "    expect(panel, contains('await store.save(updated)'));\n"
    "    expect(panel, contains('final repaired = await runtime.repair(updated)'));\n"
    "    expect(panel, contains('final status = await runtime.inspect(repaired)'));\n"
    "    expect(panel, contains('if (!status.isReady)'));\n"
    "    expect(panel, contains('if (!queue.current.isEnvironmentBlocked) return;'));\n"
    "    expect(panel, contains('await queue.resume()'));\n"
    "    expect(panel, contains('修复识别环境'));\n"
    "    expect(panel, contains('后续歌曲已保护性暂停'));",
)
