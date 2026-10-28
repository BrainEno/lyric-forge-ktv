import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';

void main() {
  test('persists library entries across repository recreation', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-library-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}中文の歌.mp3');
    await audio.writeAsBytes(const [1, 2, 3]);

    final first = FileLocalMediaLibraryRepository(rootDirectory: root);
    await first.addPaths([audio.path]);

    final second = FileLocalMediaLibraryRepository(rootDirectory: root);
    final restored = await second.getAll();

    expect(restored, hasLength(1));
    expect(restored.single.sourcePath, audio.absolute.path);
    expect(restored.single.format, 'mp3');
    expect(restored.single.isMissing, isFalse);
  });

  test('deduplicates the same source path', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-library-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}song.flac');
    await audio.writeAsBytes(const [1]);

    final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
    await repository.addPaths([audio.path, audio.path]);

    expect(await repository.getAll(), hasLength(1));
  });

  test('marks missing files without deleting their library row', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-library-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}song.wav');
    await audio.writeAsBytes(const [1]);

    final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
    await repository.addPaths([audio.path]);
    await audio.delete();

    final refreshed = await repository.refreshAvailability();
    expect(refreshed.single.isMissing, isTrue);

    final restored = FileLocalMediaLibraryRepository(rootDirectory: root);
    expect((await restored.getAll()).single.isMissing, isTrue);
  });

  test('removeMissing only removes unavailable rows', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-library-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final existing = File('${root.path}${Platform.pathSeparator}keep.m4a');
    final missing = File('${root.path}${Platform.pathSeparator}gone.aac');
    await existing.writeAsBytes(const [1]);
    await missing.writeAsBytes(const [1]);

    final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
    await repository.addPaths([existing.path, missing.path]);
    await missing.delete();
    await repository.refreshAvailability();
    await repository.removeMissing();

    final entries = await repository.getAll();
    expect(entries, hasLength(1));
    expect(entries.single.sourcePath, existing.absolute.path);
  });

  test('persists roots and discovers new songs during rescan', () async {
    final dataRoot = await Directory.systemTemp.createTemp('lyricforge-library-data-');
    final musicRoot = await Directory.systemTemp.createTemp('lyricforge-library-music-');
    addTearDown(() async {
      if (await dataRoot.exists()) await dataRoot.delete(recursive: true);
      if (await musicRoot.exists()) await musicRoot.delete(recursive: true);
    });

    final firstSong = File('${musicRoot.path}${Platform.pathSeparator}first.mp3');
    await firstSong.writeAsBytes(const [1]);

    final repository = FileLocalMediaLibraryRepository(rootDirectory: dataRoot);
    await repository.addRoot(musicRoot.path);
    await repository.refreshFromRoots(const ['mp3', 'flac']);
    expect(await repository.getAll(), hasLength(1));

    final nested = Directory('${musicRoot.path}${Platform.pathSeparator}新专辑');
    await nested.create();
    final secondSong = File('${nested.path}${Platform.pathSeparator}第二首.flac');
    await secondSong.writeAsBytes(const [2]);

    final recreated = FileLocalMediaLibraryRepository(rootDirectory: dataRoot);
    expect(await recreated.getRoots(), [musicRoot.absolute.path]);
    final rescanned = await recreated.refreshFromRoots(const ['mp3', 'flac']);

    expect(rescanned, hasLength(2));
    expect(
      rescanned.map((entry) => entry.sourcePath),
      contains(secondSong.absolute.path),
    );
  });
}
