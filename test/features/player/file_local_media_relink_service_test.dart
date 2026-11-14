import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_local_media_relink_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_store_integrity.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('relink migrates local state and preserves playlist order', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-relink-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final oldFile = File('${root.path}${Platform.pathSeparator}old.mp3');
    final newFile = File('${root.path}${Platform.pathSeparator}moved.mp3');
    final before = File('${root.path}${Platform.pathSeparator}before.mp3');
    final after = File('${root.path}${Platform.pathSeparator}after.mp3');
    for (final file in [oldFile, newFile, before, after]) {
      await file.writeAsBytes([1, 2, 3]);
    }

    final library = FileLocalMediaLibraryRepository(rootDirectory: root);
    final collections = FileLocalMediaCollectionRepository(rootDirectory: root);
    final metadata = FileLocalMediaMetadataRepository(rootDirectory: root);
    final history = FilePlayHistoryRepository(rootDirectory: root);
    final service = FileLocalMediaRelinkService(
      libraryRepository: library,
      collectionRepository: collections,
      metadataRepository: metadata,
      historyRepository: history,
      supportedExtensions: const ['mp3'],
    );

    await library.addPaths([oldFile.path]);
    await collections.setFavorite(oldFile.path, true);
    final playlist = await collections.createPlaylist('Moved songs');
    await collections.addToPlaylist(playlist.id, [
      before.path,
      oldFile.path,
      after.path,
    ]);
    await metadata.save(
      LocalMediaMetadata(
        sourcePath: oldFile.path,
        title: 'Custom title',
        artist: 'Custom artist',
        updatedAt: DateTime(2026, 10, 8, 20),
        metadata: const {'linkedProjectId': 'project-42'},
      ),
    );
    await history.savePlayHistory(
      PlayHistory(
        id: 'history-old',
        name: 'Custom title',
        artist: 'Custom artist',
        filePath: oldFile.path,
        playedAt: DateTime(2026, 10, 8, 21),
        lastPosition: const Duration(seconds: 93),
        duration: const Duration(minutes: 4),
        lastSource: AudioSourceType.original,
      ),
    );

    await oldFile.delete();
    await library.refreshAvailability();

    // Missing history is hidden from normal recent-play UI, but remains
    // recoverable so a later relink can keep resume state.
    expect(await history.getRecentPlayHistory(), isEmpty);

    final result = await service.relink(
      oldPath: oldFile.path,
      newPath: newFile.path,
    );

    expect(result.favoriteMigrated, isTrue);
    expect(result.playlistsMigrated, 1);
    expect(result.metadataMigrated, isTrue);
    expect(result.historyMigrated, isTrue);
    expect(await library.getByPath(oldFile.path), isNull);
    expect((await library.getByPath(newFile.path))?.isMissing, isFalse);
    expect(await collections.isFavorite(oldFile.path), isFalse);
    expect(await collections.isFavorite(newFile.path), isTrue);

    final updatedPlaylist = (await collections.getPlaylists()).single;
    expect(updatedPlaylist.sourcePaths, [
      File(before.path).absolute.path,
      File(newFile.path).absolute.path,
      File(after.path).absolute.path,
    ]);

    final movedMetadata = await metadata.getForAudio(newFile.path);
    expect(movedMetadata?.title, 'Custom title');
    expect(movedMetadata?.metadata['linkedProjectId'], 'project-42');
    expect(await metadata.getForAudio(oldFile.path), isNull);

    final histories = await history.getRecentPlayHistory();
    expect(histories, hasLength(1));
    expect(histories.single.filePath, File(newFile.path).absolute.path);
    expect(histories.single.lastPosition, const Duration(seconds: 93));
  });

  for (final problem in ['partial-metadata', 'destination-conflict']) {
    test('relink refuses $problem before modifying any store', () async {
      final root = await Directory.systemTemp.createTemp('relink-preflight-');
      addTearDown(() => root.delete(recursive: true));
      final oldFile = File('${root.path}${Platform.pathSeparator}old.mp3');
      final newFile = File('${root.path}${Platform.pathSeparator}new.mp3');
      await oldFile.writeAsBytes([1]);
      await newFile.writeAsBytes([2]);
      final library = FileLocalMediaLibraryRepository(rootDirectory: root);
      final collections = FileLocalMediaCollectionRepository(
        rootDirectory: root,
      );
      final history = FilePlayHistoryRepository(rootDirectory: root);
      await library.addPaths([oldFile.path]);
      await collections.setFavorite(oldFile.path, true);
      final playlist = await collections.createPlaylist('收藏');
      await collections.addToPlaylist(playlist.id, [oldFile.path]);
      await history.savePlayHistory(
        PlayHistory(
          id: 'history-old',
          name: 'Old title',
          filePath: oldFile.path,
          playedAt: DateTime(2026),
          lastPosition: const Duration(seconds: 42),
          duration: const Duration(minutes: 3),
          lastSource: AudioSourceType.original,
        ),
      );
      final old = LocalMediaMetadata(
        sourcePath: oldFile.path,
        title: '原资料',
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'original-project'},
      );
      final target = LocalMediaMetadata(
        sourcePath: newFile.path,
        title: '目标资料',
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'destination-project'},
      );
      final metadataStore = File(
        '${root.path}${Platform.pathSeparator}media_metadata.json',
      );
      final backup = File('${metadataStore.path}.bak');
      final records = problem == 'partial-metadata'
          ? [(old.toJson()..['metadata'] = 'corrupt')]
          : [old.toJson(), target.toJson()];
      await metadataStore.writeAsString(
        jsonEncode({'version': 1, 'items': records}),
      );
      await backup.writeAsString(jsonEncode({'version': 1, 'items': []}));
      final metadata = FileLocalMediaMetadataRepository(rootDirectory: root);
      await oldFile.delete();
      await library.refreshAvailability();
      final service = FileLocalMediaRelinkService(
        libraryRepository: library,
        collectionRepository: collections,
        metadataRepository: metadata,
        historyRepository: history,
        supportedExtensions: const ['mp3'],
      );
      final paths = [
        'media_library.json',
        'library_collections.json',
        'play_history.json',
        'media_metadata.json',
        'media_metadata.json.bak',
      ];
      final before = <String, String>{};
      for (final path in paths) {
        before[path] = await File(
          '${root.path}${Platform.pathSeparator}$path',
        ).readAsString();
      }

      await expectLater(
        service.relink(oldPath: oldFile.path, newPath: newFile.path),
        problem == 'partial-metadata'
            ? throwsFormatException
            : throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  contains('目标音频已有歌曲资料'),
                ),
              ),
      );
      for (final path in paths) {
        expect(
          await File(
            '${root.path}${Platform.pathSeparator}$path',
          ).readAsString(),
          before[path],
          reason: path,
        );
      }
      expect(await library.getByPath(oldFile.path), isNotNull);
      expect(await library.getByPath(newFile.path), isNull);
      expect(await collections.isFavorite(oldFile.path), isTrue);
      expect(await collections.isFavorite(newFile.path), isFalse);
      expect((await collections.getPlaylists()).single.sourcePaths, [
        oldFile.absolute.path,
      ]);
      if (problem == 'destination-conflict') {
        expect(
          (await metadata.getForAudio(
            oldFile.path,
          ))?.metadata['linkedProjectId'],
          'original-project',
        );
        expect(
          (await metadata.getForAudio(
            newFile.path,
          ))?.metadata['linkedProjectId'],
          'destination-project',
        );
      }
    });
  }

  test(
    'relink refuses a partly readable collection store before any write',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'relink-incomplete-collections-',
      );
      addTearDown(() => root.delete(recursive: true));
      final oldFile = File('${root.path}${Platform.pathSeparator}old.mp3');
      final newFile = File('${root.path}${Platform.pathSeparator}new.mp3');
      await oldFile.writeAsBytes([1]);
      await newFile.writeAsBytes([2]);
      final library = FileLocalMediaLibraryRepository(rootDirectory: root);
      final history = FilePlayHistoryRepository(rootDirectory: root);
      await library.addPaths([oldFile.path]);
      final seeded = FileLocalMediaCollectionRepository(rootDirectory: root);
      await seeded.setFavorite(oldFile.path, true);
      final playlist = await seeded.createPlaylist('收藏');
      await seeded.addToPlaylist(playlist.id, [oldFile.path]);

      // Append a playlist row this version cannot read (#439). Relinking must
      // not move the favorite because the follow-up write would drop the row.
      final collectionsFile = File(
        '${root.path}${Platform.pathSeparator}library_collections.json',
      );
      final payload =
          jsonDecode(await collectionsFile.readAsString())
              as Map<String, dynamic>;
      (payload['playlists'] as List).add({'id': 42, 'name': 'future'});
      await collectionsFile.writeAsString(jsonEncode(payload));

      await oldFile.delete();
      await library.refreshAvailability();
      final collections = FileLocalMediaCollectionRepository(
        rootDirectory: root,
      );
      final service = FileLocalMediaRelinkService(
        libraryRepository: library,
        collectionRepository: collections,
        metadataRepository: FileLocalMediaMetadataRepository(
          rootDirectory: root,
        ),
        historyRepository: history,
        supportedExtensions: const ['mp3'],
      );
      final libraryFile = File(
        '${root.path}${Platform.pathSeparator}media_library.json',
      );
      final libraryBefore = await libraryFile.readAsString();
      final collectionsBefore = await collectionsFile.readAsString();

      await expectLater(
        service.relink(oldPath: oldFile.path, newPath: newFile.path),
        throwsA(
          isA<LocalStoreIncompleteException>().having(
            (e) => e.issue.kind,
            'kind',
            LocalStoreKind.collections,
          ),
        ),
      );

      expect(await libraryFile.readAsString(), libraryBefore);
      expect(await collectionsFile.readAsString(), collectionsBefore);
      expect(await library.getByPath(newFile.path), isNull);
      expect(await collections.isFavorite(oldFile.path), isTrue);
    },
  );

  test(
    'relink with no old metadata preserves existing destination metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'relink-existing-target-',
      );
      addTearDown(() => root.delete(recursive: true));
      final oldFile = File('${root.path}${Platform.pathSeparator}old.mp3');
      final newFile = File('${root.path}${Platform.pathSeparator}new.mp3');
      await oldFile.writeAsBytes([1]);
      await newFile.writeAsBytes([2]);
      final library = FileLocalMediaLibraryRepository(rootDirectory: root);
      final collections = FileLocalMediaCollectionRepository(
        rootDirectory: root,
      );
      final metadata = FileLocalMediaMetadataRepository(rootDirectory: root);
      final history = FilePlayHistoryRepository(rootDirectory: root);
      await library.addPaths([oldFile.path]);
      await collections.setFavorite(oldFile.path, true);
      await metadata.save(
        LocalMediaMetadata(
          sourcePath: newFile.path,
          title: '保留目标资料',
          updatedAt: DateTime(2026),
          metadata: const {'linkedProjectId': 'destination-project'},
        ),
      );
      await oldFile.delete();
      await library.refreshAvailability();
      final service = FileLocalMediaRelinkService(
        libraryRepository: library,
        collectionRepository: collections,
        metadataRepository: metadata,
        historyRepository: history,
        supportedExtensions: const ['mp3'],
      );
      final result = await service.relink(
        oldPath: oldFile.path,
        newPath: newFile.path,
      );
      expect(result.metadataMigrated, isFalse);
      expect(await library.getByPath(oldFile.path), isNull);
      expect(await collections.isFavorite(newFile.path), isTrue);
      expect((await metadata.getForAudio(newFile.path))?.title, '保留目标资料');
      expect(
        (await metadata.getForAudio(newFile.path))?.metadata['linkedProjectId'],
        'destination-project',
      );
    },
  );
}
