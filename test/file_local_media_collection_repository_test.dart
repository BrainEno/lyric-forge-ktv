import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_collection_repository.dart';

void main() {
  group('FileLocalMediaCollectionRepository', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lyricforge-collections-');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('persists Unicode favorites across repository recreation', () async {
      final path = '${directory.path}${Platform.pathSeparator}宇多田ヒカル - First Love.mp3';
      final first = FileLocalMediaCollectionRepository(rootDirectory: directory);

      expect(await first.setFavorite(path, true), isTrue);
      expect(await first.isFavorite(path), isTrue);

      final restored = FileLocalMediaCollectionRepository(rootDirectory: directory);
      final favorites = await restored.getFavoritePaths();
      expect(favorites, hasLength(1));
      expect(favorites.single, File(path).absolute.path);
      expect(await restored.isFavorite(path), isTrue);
    });

    test('playlist membership is ordered and de-duplicates paths', () async {
      final repository = FileLocalMediaCollectionRepository(rootDirectory: directory);
      final playlist = await repository.createPlaylist('夜のドライブ 🎵');
      final first = '${directory.path}${Platform.pathSeparator}夜に駆ける.mp3';
      final second = '${directory.path}${Platform.pathSeparator}夜曲.flac';

      final updated = await repository.addToPlaylist(
        playlist.id,
        [first, second, first],
      );

      expect(updated.sourcePaths, [
        File(first).absolute.path,
        File(second).absolute.path,
      ]);

      final restored = FileLocalMediaCollectionRepository(rootDirectory: directory);
      final playlists = await restored.getPlaylists();
      expect(playlists.single.name, '夜のドライブ 🎵');
      expect(playlists.single.sourcePaths, updated.sourcePaths);
    });

    test('keeps unavailable source references instead of deleting user intent', () async {
      final repository = FileLocalMediaCollectionRepository(rootDirectory: directory);
      final playlist = await repository.createPlaylist('移动硬盘');
      final missing = '${directory.path}${Platform.pathSeparator}离线歌曲.mp3';

      final updated = await repository.addToPlaylist(playlist.id, [missing]);
      expect(updated.sourcePaths, [File(missing).absolute.path]);

      final restored = FileLocalMediaCollectionRepository(rootDirectory: directory);
      expect((await restored.getPlaylists()).single.sourcePaths, updated.sourcePaths);
    });

    test('supports rename reorder remove and delete without touching files', () async {
      final first = File('${directory.path}${Platform.pathSeparator}A.mp3');
      final second = File('${directory.path}${Platform.pathSeparator}B.mp3');
      await first.writeAsBytes([1]);
      await second.writeAsBytes([2]);

      final repository = FileLocalMediaCollectionRepository(rootDirectory: directory);
      var playlist = await repository.createPlaylist('Draft');
      playlist = await repository.addToPlaylist(
        playlist.id,
        [first.path, second.path],
      );
      playlist = await repository.moveInPlaylist(playlist.id, 1, 0);
      expect(playlist.sourcePaths.first, second.absolute.path);

      playlist = await repository.renamePlaylist(playlist.id, '正式歌单');
      expect(playlist.name, '正式歌单');

      playlist = await repository.removeFromPlaylist(playlist.id, first.path);
      expect(playlist.sourcePaths, [second.absolute.path]);
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isTrue);

      await repository.deletePlaylist(playlist.id);
      expect(await repository.getPlaylists(), isEmpty);
      expect(await second.exists(), isTrue);
    });

    test('emits revisions after persisted collection mutations', () async {
      final repository = FileLocalMediaCollectionRepository(rootDirectory: directory);
      final path = '${directory.path}${Platform.pathSeparator}同步测试.mp3';
      final revisions = <int>[];
      final subscription = repository.changes.listen(revisions.add);

      await repository.setFavorite(path, true);
      final playlist = await repository.createPlaylist('同步歌单');
      await repository.addToPlaylist(playlist.id, [path]);
      await Future<void>.delayed(Duration.zero);

      expect(revisions, [1, 2, 3]);
      await subscription.cancel();
    });
  });
}
