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

  test('queue UI exposes environment repair path and protective copy', () async {
    final panel = await File(
      'lib/features/transcription/presentation/widgets/'
      'transcription_queue_panel.dart',
    ).readAsString();
    final queue = await File(
      'lib/features/transcription/data/services/'
      'file_batch_transcription_queue.dart',
    ).readAsString();

    expect(panel, contains('state.isEnvironmentBlocked'));
    expect(panel, contains('AsrRuntimeSetupDialog(initialConfig: current)'));
    expect(panel, contains('await store.save(updated)'));
    expect(panel, contains('final repaired = await runtime.repair(updated)'));
    expect(panel, contains('final status = await runtime.inspect(repaired)'));
    expect(panel, contains('if (!status.isReady)'));
    expect(panel, contains('if (!queue.current.isEnvironmentBlocked) return;'));
    expect(panel, contains('await queue.resume()'));
    expect(panel, contains('修复识别环境'));
    expect(panel, contains('后续歌曲已保护性暂停'));

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
