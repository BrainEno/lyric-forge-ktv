import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  group('FilePlayHistoryRepository', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lyricforge-history-test-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('history survives repository recreation with resume position', () async {
      final audio = File('${root.path}${Platform.pathSeparator}song.mp3');
      await audio.writeAsBytes([1, 2, 3]);
      final first = FilePlayHistoryRepository(rootDirectory: root);

      await first.savePlayHistory(
        _history(
          id: 'one',
          path: audio.path,
          position: const Duration(seconds: 73),
        ),
      );

      final restored = FilePlayHistoryRepository(rootDirectory: root);
      final histories = await restored.getRecentPlayHistory();

      expect(histories, hasLength(1));
      expect(histories.single.filePath, audio.path);
      expect(histories.single.lastPosition, const Duration(seconds: 73));
      expect(histories.single.duration, const Duration(minutes: 4));
    });

    test('saving same file replaces the older record instead of duplicating it',
        () async {
      final audio = File('${root.path}${Platform.pathSeparator}same.mp3');
      await audio.writeAsBytes([1]);
      final repository = FilePlayHistoryRepository(rootDirectory: root);

      await repository.savePlayHistory(
        _history(
          id: 'old',
          path: audio.path,
          position: const Duration(seconds: 10),
        ),
      );
      await repository.savePlayHistory(
        _history(
          id: 'new',
          path: audio.path,
          position: const Duration(seconds: 45),
        ),
      );

      final histories = await repository.getRecentPlayHistory();
      expect(histories, hasLength(1));
      expect(histories.single.id, 'new');
      expect(histories.single.lastPosition, const Duration(seconds: 45));
    });

    test('missing local history is hidden but can be relinked later', () async {
      final audio = File('${root.path}${Platform.pathSeparator}missing.mp3');
      final replacement = File('${root.path}${Platform.pathSeparator}moved.mp3');
      await audio.writeAsBytes([1]);
      await replacement.writeAsBytes([2]);
      final repository = FilePlayHistoryRepository(rootDirectory: root);
      await repository.savePlayHistory(
        _history(
          id: 'missing',
          path: audio.path,
          position: const Duration(seconds: 30),
        ),
      );

      await audio.delete();
      expect(await repository.getRecentPlayHistory(), isEmpty);
      expect(
        await repository.replaceLocalPath(
          oldPath: audio.path,
          newPath: replacement.path,
        ),
        isTrue,
      );

      final restored = FilePlayHistoryRepository(rootDirectory: root);
      final histories = await restored.getRecentPlayHistory();
      expect(histories, hasLength(1));
      expect(histories.single.filePath, replacement.absolute.path);
      expect(histories.single.lastPosition, const Duration(seconds: 30));
    });

    test('remote stream URLs are never persisted as local recent history', () async {
      final repository = FilePlayHistoryRepository(rootDirectory: root);

      await repository.savePlayHistory(
        _history(
          id: 'remote',
          path: 'http://192.168.1.8:48517/v1/tracks/remote/audio?token=test',
          position: const Duration(seconds: 31),
        ),
      );

      expect(await repository.getRecentPlayHistory(), isEmpty);
      final restored = FilePlayHistoryRepository(rootDirectory: root);
      expect(await restored.getRecentPlayHistory(), isEmpty);
    });

    test('clear removes persisted history', () async {
      final audio = File('${root.path}${Platform.pathSeparator}clear.mp3');
      await audio.writeAsBytes([1]);
      final repository = FilePlayHistoryRepository(rootDirectory: root);
      await repository.savePlayHistory(
        _history(id: 'clear', path: audio.path, position: Duration.zero),
      );

      await repository.clearPlayHistory();

      final restored = FilePlayHistoryRepository(rootDirectory: root);
      expect(await restored.getRecentPlayHistory(), isEmpty);
    });
  });
}

PlayHistory _history({
  required String id,
  required String path,
  required Duration position,
}) {
  return PlayHistory(
    id: id,
    name: 'Song',
    artist: 'Artist',
    filePath: path,
    playedAt: DateTime(2026, 10, 4, 12),
    lastPosition: position,
    duration: const Duration(minutes: 4),
    lastSource: AudioSourceType.original,
  );
}
