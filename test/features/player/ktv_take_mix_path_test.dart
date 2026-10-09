import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/ktv_take_history_store.dart';

void main() {
  test('history exposes only an in-take regular mix.wav', () async {
    final root = await Directory.systemTemp.createTemp('ktv-mix-path-');
    try {
      final recordings = Directory(
        '${root.path}${Platform.pathSeparator}recordings',
      );
      await recordings.create();
      final external = File('${root.path}${Platform.pathSeparator}external.wav');
      await external.writeAsBytes([9, 8, 7]);

      Future<void> writeTake(
        String id,
        String startedAt, {
        required String? Function(Directory takeDir) mixedPath,
        bool createExpectedMix = false,
      }) async {
        final takeDir = Directory(
          '${recordings.path}${Platform.pathSeparator}$id',
        );
        await takeDir.create();
        final voice = File(
          '${takeDir.path}${Platform.pathSeparator}voice.wav',
        );
        await voice.writeAsBytes([0, 1]);
        final mix = File('${takeDir.path}${Platform.pathSeparator}mix.wav');
        if (createExpectedMix) await mix.writeAsBytes([2, 3]);
        final manifest = File(
          '${takeDir.path}${Platform.pathSeparator}session.json',
        );
        await manifest.writeAsString(jsonEncode({
          'version': 1,
          'id': id,
          'projectId': 'song',
          'startedAt': startedAt,
          'completedAt': '2026-10-09T12:01:00.000',
          'backingSource': 'original',
          'backingPath': 'song.wav',
          'startPositionMs': 0,
          'durationMs': 1000,
          'micStemPath': voice.path,
          'manifestPath': manifest.path,
          'mixedOutputPath': mixedPath(takeDir),
          'backingVolume': 1,
          'monitorMicGain': 1,
          'alignmentReliable': true,
          'alignmentIssue': null,
        }));
      }

      await writeTake(
        'take_safe',
        '2026-10-09T12:03:00.000',
        mixedPath: (dir) => '${dir.path}${Platform.pathSeparator}mix.wav',
        createExpectedMix: true,
      );
      await writeTake(
        'take_external',
        '2026-10-09T12:02:00.000',
        mixedPath: (_) => external.path,
      );
      await writeTake(
        'take_missing',
        '2026-10-09T12:01:00.000',
        mixedPath: (dir) => '${dir.path}${Platform.pathSeparator}mix.wav',
      );

      final takes = await const KtvTakeHistoryStore()
          .listFromDirectory(root, 'song');
      expect(takes, hasLength(3));
      expect(
        takes.firstWhere((take) => take.id == 'take_safe').mixedOutputPath,
        endsWith('${Platform.pathSeparator}mix.wav'),
      );
      expect(
        takes.firstWhere((take) => take.id == 'take_external').mixedOutputPath,
        isNull,
      );
      expect(
        takes.firstWhere((take) => take.id == 'take_missing').mixedOutputPath,
        isNull,
      );
      expect(await external.readAsBytes(), [9, 8, 7]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
