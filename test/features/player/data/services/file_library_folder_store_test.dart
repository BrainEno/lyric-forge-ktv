import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_library_folder_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-folder-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  String at(String relative) =>
      '${root.path}${Platform.pathSeparator}$relative';

  Future<void> touch(String relative) async {
    final file = File(at(relative));
    await file.parent.create(recursive: true);
    await file.writeAsString('[00:01.00]歌词');
  }

  group('FileLibraryFolderStore', () {
    test('remembers a folder and forgets it again', () async {
      final store = FileLibraryFolderStore(rootDirectory: root);

      expect(await store.loadFolder(), isNull);
      await store.saveFolder('  /mnt/曲库 ');
      expect(await store.loadFolder(), '/mnt/曲库');
      expect(
        await FileLibraryFolderStore(rootDirectory: root).loadFolder(),
        '/mnt/曲库',
      );

      await store.saveFolder(null);
      expect(await store.loadFolder(), isNull);
      expect(File(at(FileLibraryFolderStore.fileName)).existsSync(), isFalse);
    });

    test('a damaged file falls back to the default', () async {
      await File(at(FileLibraryFolderStore.fileName)).writeAsString('{oops');

      final store = FileLibraryFolderStore(rootDirectory: root);

      expect(await store.loadFolder(), isNull);
    });

    test('a file of the wrong shape falls back to the default', () async {
      final file = File(at(FileLibraryFolderStore.fileName));
      await file.writeAsString('{"folder": 42}');

      final store = FileLibraryFolderStore(rootDirectory: root);

      expect(await store.loadFolder(), isNull);
    });
  });

  group('listLyricFiles', () {
    const lyrics = {'lrc', 'srt'};

    test('lists matching files, deeply when asked', () async {
      await touch('夜曲.lrc');
      await touch('晴天.SRT');
      await touch('notes.txt');
      await touch('周杰伦/稻香.lrc');

      final flat = await listLyricFiles(
        root.path,
        recursive: false,
        extensions: lyrics,
      );
      final deep = await listLyricFiles(
        root.path,
        recursive: true,
        extensions: lyrics,
      );

      expect(flat, unorderedEquals([at('夜曲.lrc'), at('晴天.SRT')]));
      expect(deep, hasLength(3));
      expect(deep, contains(at('周杰伦${Platform.pathSeparator}稻香.lrc')));
    });

    test('skips hidden folders and files without a name', () async {
      await touch('.Trash/旧.lrc');
      await touch('.lrc');
      await touch('可见.lrc');

      final found = await listLyricFiles(
        root.path,
        recursive: true,
        extensions: lyrics,
      );

      expect(found, [at('可见.lrc')]);
    });

    test('a folder that does not exist lists nothing', () async {
      final found = await listLyricFiles(
        at('missing'),
        recursive: true,
        extensions: lyrics,
      );

      expect(found, isEmpty);
    });
  });
}
