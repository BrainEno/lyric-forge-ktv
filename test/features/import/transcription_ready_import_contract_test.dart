import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import route is guarded by desktop transcription readiness', () {
    final router = File('lib/core/navigation/app_router.dart').readAsStringSync();
    final gate = File(
      'lib/features/import/presentation/screens/'
      'transcription_ready_import_screen.dart',
    ).readAsStringSync();

    expect(
      router,
      contains('return _fadeRoute(const TranscriptionReadyImportScreen()'),
    );
    expect(gate, contains('TranscriptionEnvironmentPreflight('));
    expect(gate, contains('AsrRuntimeSetupDialog('));
    expect(gate, contains('Navigator.pushNamed(context, Routes.settings)'));
    expect(
      gate,
      contains('if (!_isDesktop) return const ImportAudioScreen();'),
      reason: 'mobile import behavior must stay unchanged',
    );
    expect(
      gate,
      contains('if (readiness?.isReady == true)'),
      reason: 'desktop import should only open after runtime readiness',
    );
  });

  test('environment-blocked queue remains a final safety net', () {
    final gate = File(
      'lib/features/import/presentation/screens/'
      'transcription_ready_import_screen.dart',
    ).readAsStringSync();
    final queue = File(
      'lib/features/transcription/data/services/'
      'file_batch_transcription_queue.dart',
    ).readAsStringSync();

    expect(queue, contains('else if (_isEnvironmentBlocked(error))'));
    expect(queue, contains('_paused = true;'));
    expect(
      queue,
      contains('_pauseReason = TranscriptionQueuePauseReason.environment;'),
    );
    expect(queue, contains('_pauseMessage = error.toString();'));
    expect(queue, contains('error.blocksQueue'));
    expect(
      gate,
      contains('if (!snapshot.isEnvironmentBlocked || snapshot.isProcessing) return;'),
      reason: 'only structured environment pauses may auto-resume after setup',
    );
    expect(
      gate,
      isNot(contains("item.message.contains('等待本地识别环境')")),
      reason: 'queue recovery must not depend on user-facing Chinese copy',
    );
    expect(gate, contains('await queue.resume();'));
  });
}
