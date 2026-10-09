import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/ktv_take_history_store.dart';

void main() {
  test('ignores corrupt takes and keeps valid take order', () async {
    final root = await Directory.systemTemp.createTemp('ktv-history-');
    try {
      final recordings = Directory('${root.path}${Platform.pathSeparator}recordings');
      await recordings.create();
      for (final n in [1, 2]) {
        final dir = Directory('${recordings.path}${Platform.pathSeparator}take_$n');
        await dir.create();
        final voice = File('${dir.path}${Platform.pathSeparator}voice.wav');
        await voice.writeAsBytes([0, 1]);
        final manifest = File('${dir.path}${Platform.pathSeparator}session.json');
        await manifest.writeAsString(jsonEncode({
          'id': 'take_$n', 'projectId': 'song',
          'startedAt': '2026-10-0$n' 'T12:00:00.000',
          'completedAt': '2026-10-0$n' 'T12:01:00.000',
          'backingSource': 'original', 'backingPath': 'song.wav',
          'startPositionMs': 0, 'durationMs': 1000,
          'micStemPath': voice.path, 'manifestPath': manifest.path,
          'backingVolume': 1, 'monitorMicGain': 1,
        }));
      }
      final bad = Directory('${recordings.path}${Platform.pathSeparator}take_bad');
      await bad.create();
      await File('${bad.path}${Platform.pathSeparator}session.json').writeAsString('{');
      final external = File('${root.path}${Platform.pathSeparator}important.wav');
      await external.writeAsBytes([7, 8, 9]);
      final forgedDir = Directory('${recordings.path}${Platform.pathSeparator}take_forged');
      await forgedDir.create();
      final forgedManifest = File('${forgedDir.path}${Platform.pathSeparator}session.json');
      await forgedManifest.writeAsString(jsonEncode({
        'id': 'take_forged', 'projectId': 'song',
        'startedAt': '2026-10-03T12:00:00.000',
        'completedAt': '2026-10-03T12:01:00.000',
        'backingSource': 'original', 'backingPath': 'song.wav',
        'startPositionMs': 0, 'durationMs': 1000,
        'micStemPath': external.path, 'manifestPath': forgedManifest.path,
        'backingVolume': 1, 'monitorMicGain': 1,
      }));
      final history = await const KtvTakeHistoryStore().listFromDirectory(root, 'song');
      expect(history.map((e) => e.id).toList(), ['take_2', 'take_1']);
      expect(await const KtvTakeHistoryStore().listFromDirectory(root, 'other'), isEmpty);
      expect(await external.readAsBytes(), [7, 8, 9]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
