import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/ktv_take_history_store.dart';
import 'package:lyric_forge_ktv/features/player/data/services/pcm16_wav_writer.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

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
      final first = history.firstWhere((take) => take.id == 'take_1');
      await const KtvTakeHistoryStore().deleteTake(root, 'song', first);
      expect(await Directory('${recordings.path}${Platform.pathSeparator}take_1').exists(), isFalse);
      expect(await Directory('${recordings.path}${Platform.pathSeparator}take_2').exists(), isTrue);
      expect(await external.readAsBytes(), [7, 8, 9]);
      await expectLater(
        const KtvTakeHistoryStore().deleteTake(root, 'other', first),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('take names and favorites persist and favorites sort first', () async {
    final root = await Directory.systemTemp.createTemp('ktv-metadata-');
    try {
      final recordings = Directory('${root.path}${Platform.pathSeparator}recordings');
      await recordings.create();
      for (final entry in [
        ('take_old', '2026-10-01T12:00:00.000'),
        ('take_new', '2026-10-02T12:00:00.000'),
      ]) {
        final dir = Directory(
          '${recordings.path}${Platform.pathSeparator}${entry.$1}',
        );
        await dir.create();
        final voice = File('${dir.path}${Platform.pathSeparator}voice.wav');
        await voice.writeAsBytes([0, 1]);
        final manifest = File('${dir.path}${Platform.pathSeparator}session.json');
        await manifest.writeAsString(jsonEncode({
          'version': 1,
          'id': entry.$1,
          'projectId': 'song',
          'startedAt': entry.$2,
          'completedAt': '2026-10-02T12:01:00.000',
          'backingSource': 'original',
          'backingPath': 'song.wav',
          'startPositionMs': 0,
          'durationMs': 1000,
          'micStemPath': voice.path,
          'manifestPath': manifest.path,
          'mixedOutputPath': null,
          'backingVolume': 1,
          'monitorMicGain': 1,
          'alignmentReliable': true,
          'alignmentIssue': null,
        }));
      }

      const store = KtvTakeHistoryStore();
      final initial = await store.listFromDirectory(root, 'song');
      expect(initial.map((take) => take.id), ['take_new', 'take_old']);
      expect(initial.every((take) => take.displayName == null), isTrue);
      expect(initial.every((take) => !take.isFavorite), isTrue);

      final older = initial.firstWhere((take) => take.id == 'take_old');
      final updated = await store.updateTakeMetadata(
        root,
        'song',
        older,
        displayName: '  Best chorus  ',
        isFavorite: true,
      );
      expect(updated.displayName, 'Best chorus');
      expect(updated.isFavorite, isTrue);

      final rescanned = await store.listFromDirectory(root, 'song');
      expect(rescanned.map((take) => take.id), ['take_old', 'take_new']);
      expect(rescanned.first.displayName, 'Best chorus');
      expect(rescanned.first.isFavorite, isTrue);
      final persisted = jsonDecode(
        await File(rescanned.first.manifestPath).readAsString(),
      ) as Map<String, dynamic>;
      expect(persisted['displayName'], 'Best chorus');
      expect(persisted['isFavorite'], isTrue);

      final cleared = await store.updateTakeMetadata(
        root,
        'song',
        rescanned.first,
        displayName: '   ',
        isFavorite: false,
      );
      expect(cleared.displayName, isNull);
      expect(cleared.isFavorite, isFalse);

      await expectLater(
        store.updateTakeMetadata(
          root,
          'song',
          cleared,
          displayName: 'x' * (KtvTakeHistoryStore.maxDisplayNameLength + 1),
        ),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('project-level scan recovers once and project-level delete uses same root', () async {
    final root = await Directory.systemTemp.createTemp('ktv-recovery-');
    try {
      final takeDir = Directory(
        '${root.path}${Platform.pathSeparator}recordings'
        '${Platform.pathSeparator}take_interrupted',
      );
      await takeDir.create(recursive: true);
      final voice = File('${takeDir.path}${Platform.pathSeparator}voice.wav');
      final writer = Pcm16WavWriter();
      await writer.open(voice.path);
      writer.addPcm16(Uint8List(9600));
      await writer.close();

      final interruptedBytes = await voice.readAsBytes();
      for (final offset in [4, 5, 6, 7, 40, 41, 42, 43]) {
        interruptedBytes[offset] = 0;
      }
      await voice.writeAsBytes(interruptedBytes, flush: true);
      final originalPcm = interruptedBytes.sublist(44);

      final manifest = File(
        '${takeDir.path}${Platform.pathSeparator}session.json',
      );
      await manifest.writeAsString(jsonEncode({
        'version': 1,
        'id': 'take_interrupted',
        'projectId': 'song',
        'startedAt': '2026-10-09T12:00:00.000',
        'completedAt': null,
        'backingSource': 'original',
        'backingPath': 'song.wav',
        'startPositionMs': 0,
        'durationMs': 0,
        'micStemPath': voice.path,
        'manifestPath': manifest.path,
        'mixedOutputPath': null,
        'backingVolume': 1,
        'monitorMicGain': 1,
        'alignmentReliable': true,
        'alignmentIssue': null,
      }));

      final project = ProjectManifest(
        id: 'song',
        name: 'Song',
        createdAt: DateTime(2026, 10, 9),
        updatedAt: DateTime(2026, 10, 9),
        projectDirectory: root.path,
      );
      const store = KtvTakeHistoryStore();
      final firstScan = await store.scanProject(project);
      expect(firstScan.recoveredCount, 1);
      expect(firstScan.takes, hasLength(1));
      final recovered = firstScan.takes.single;
      expect(recovered.duration, const Duration(milliseconds: 100));
      expect(recovered.completedAt, isNotNull);
      expect(recovered.alignmentReliable, isFalse);
      expect(recovered.alignmentIssue, contains('已恢复原始人声'));
      expect((await voice.readAsBytes()).sublist(44), originalPcm);

      final persisted = jsonDecode(await manifest.readAsString())
          as Map<String, dynamic>;
      expect(persisted['durationMs'], 100);
      expect(persisted['completedAt'], isNotNull);
      expect(persisted['alignmentReliable'], isFalse);

      final secondScan = await store.scanProject(project);
      expect(secondScan.recoveredCount, 0);
      expect(secondScan.takes.single.duration,
          const Duration(milliseconds: 100));

      await store.deleteProjectTake(project, secondScan.takes.single);
      expect(await takeDir.exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
