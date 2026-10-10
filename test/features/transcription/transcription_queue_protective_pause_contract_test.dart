import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  test('structured failure kinds distinguish environment from song input', () {
    const environment = TranscriptionException.environment(
      'GPU driver unavailable',
    );
    const input = TranscriptionException.input('audio file is corrupt');

    expect(environment.kind, TranscriptionFailureKind.environment);
    expect(environment.blocksQueue, isTrue);
    expect(input.kind, TranscriptionFailureKind.input);
    expect(input.blocksQueue, isFalse);
  });

  test('queue UI exposes closed-loop environment repair and protective copy',
      () async {
    final panel = await File(
      'lib/features/transcription/presentation/widgets/'
      'transcription_queue_panel.dart',
    ).readAsString();
    final recovery = await File(
      'lib/features/transcription/domain/services/'
      'transcription_queue_environment_recovery.dart',
    ).readAsString();
    final queue = await File(
      'lib/features/transcription/data/services/'
      'file_batch_transcription_queue.dart',
    ).readAsString();

    expect(panel, contains('state.isEnvironmentBlocked'));
    expect(panel, contains('AsrRuntimeSetupDialog(initialConfig: current)'));
    expect(panel, contains('TranscriptionQueueEnvironmentRecovery('));
    expect(panel, contains('final result = await recovery.recover(updated)'));
    expect(panel, contains('if (!result.ready)'));
    expect(panel, contains('if (!result.resumed)'));
    expect(panel, contains('识别环境已恢复，后台队列已继续'));
    expect(panel, contains('修复识别环境'));
    expect(panel, contains('后续歌曲已保护性暂停'));

    expect(recovery, contains('await settingsStore.save(config)'));
    expect(recovery, contains('final repaired = await runtimeManager.repair(config)'));
    expect(recovery, contains('final status = await runtimeManager.inspect(repaired)'));
    expect(recovery, contains('if (!status.isReady)'));
    expect(recovery, contains('if (!queue.current.isEnvironmentBlocked)'));
    expect(recovery, contains('await queue.resume()'));

    expect(queue, contains('error.blocksQueue'));
    expect(queue, contains('TranscriptionQueuePauseReason.environment'));
    expect(queue, contains("'pauseReason': _pauseReason?.name"));
    expect(queue, contains("'pauseMessage': _pauseMessage"));
  });

  test('workflow tags runtime preflight failures and persists failure kind',
      () async {
    final workflow = await File(
      'lib/features/transcription/data/services/'
      'local_project_transcription_workflow.dart',
    ).readAsString();

    expect(workflow, contains('TranscriptionException.environment('));
    expect(
      workflow,
      contains('error.withKind(TranscriptionFailureKind.environment)'),
    );
    expect(workflow, contains("'kind': error.kind.name"));
  });
}
