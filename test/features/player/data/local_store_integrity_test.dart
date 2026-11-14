import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_store_integrity.dart';

/// #439: a partly readable library or collection file must never be replaced
/// by the readable subset. #440: a failed first load must not be cached.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lyricforge-store-integrity-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  String inRoot(String name) => '${root.path}${Platform.pathSeparator}$name';

  Future<File> audio(String name) async {
    final file = File(inRoot(name));
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }

  group('FileLocalMediaLibraryRepository partial loads (#439)', () {
    Future<File> libraryWithBrokenRow() async {
      final first = await audio('第一首.mp3');
      final second = await audio('second.flac');
      final seed = FileLocalMediaLibraryRepository(rootDirectory: root);
      await seed.addPaths([first.path, second.path]);
      await seed.addRoot(root.path);
      final store = File(inRoot('media_library.json'));
      final decoded = jsonDecode(await store.readAsString()) as Map;
      (decoded['entries'] as List)
        ..add({'sourcePath': 42, 'format': 'mp3'})
        ..add('not an object');
      await store.writeAsString(jsonEncode(decoded));
      return store;
    }

    test('shows readable rows and reports unreadable ones', () async {
      await libraryWithBrokenRow();
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);

      final entries = await repository.getAll();
      expect(entries, hasLength(2));
      expect(await repository.getRoots(), [Directory(root.path).absolute.path]);

      final issue = await repository.loadIssue();
      expect(issue, isNotNull);
      expect(issue!.kind, LocalStoreKind.mediaLibrary);
      expect(issue.unreadableRecords, 2);
      expect(issue.readableRecords, 3);
      expect(issue.storePath, inRoot('media_library.json'));
    });

    test('refuses every write and keeps the original bytes', () async {
      final store = await libraryWithBrokenRow();
      final original = await store.readAsString();
      final backup = File('${store.path}.bak');
      final backupBefore = await backup.readAsString();
      final extra = await audio('extra.mp3');
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);

      await expectLater(
        repository.addPaths([extra.path]),
        throwsA(isA<LocalStoreIncompleteException>()),
      );
      await expectLater(
        repository.addRoot(inRoot('more')),
        throwsA(isA<LocalStoreIncompleteException>()),
      );
      await expectLater(
        repository.remove(inRoot('第一首.mp3')),
        throwsA(isA<LocalStoreIncompleteException>()),
      );
      await expectLater(
        repository.removeMissing(),
        throwsA(isA<LocalStoreIncompleteException>()),
      );

      // Refreshes stay browsable without scanning or writing.
      await File(inRoot('second.flac')).delete();
      final refreshed = await repository.refreshAvailability();
      expect(refreshed, hasLength(2));
      expect(await repository.refreshFromRoots(const ['mp3']), hasLength(2));
      expect(await repository.refreshMetadata(force: true), hasLength(2));
      expect(await repository.getByPath(extra.path), isNull);

      expect(await store.readAsString(), original);
      // Refused writes must not roll the original into `.bak` either.
      expect(await backup.readAsString(), backupBefore);
    });

    test('repair keeps a verified copy, then readable rows', () async {
      final store = await libraryWithBrokenRow();
      final original = await store.readAsBytes();
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
      await repository.getAll();

      final result = await repository.repairKeepingReadableRecords();

      expect(result.keptRecords, 3);
      expect(result.droppedRecords, 2);
      expect(
        result.preservedCopyPath,
        contains('media_library.json.incomplete-'),
      );
      expect(await File(result.preservedCopyPath).readAsBytes(), original);
      expect(await repository.loadIssue(), isNull);

      final extra = await audio('extra.mp3');
      expect(await repository.addPaths([extra.path]), hasLength(3));

      final reopened = FileLocalMediaLibraryRepository(rootDirectory: root);
      expect(await reopened.getAll(), hasLength(3));
      expect(await reopened.loadIssue(), isNull);
      // The preserved copy still holds the rows the repair dropped.
      final preservedText = await File(result.preservedCopyPath).readAsString();
      final preserved = jsonDecode(preservedText) as Map;
      expect(preserved['entries'], hasLength(4));
    });

    test('repair without an issue is refused', () async {
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
      await repository.addPaths([(await audio('ok.mp3')).path]);
      await expectLater(
        repository.repairKeepingReadableRecords(),
        throwsStateError,
      );
    });

    test('a complete store reports no issue and stays writable', () async {
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
      await repository.addPaths([(await audio('ok.mp3')).path]);
      final reopened = FileLocalMediaLibraryRepository(rootDirectory: root);
      expect(await reopened.loadIssue(), isNull);
      await reopened.addPaths([(await audio('two.mp3')).path]);
      expect(await reopened.getAll(), hasLength(2));
    });
  });

  group('FileLocalMediaCollectionRepository partial loads (#439)', () {
    Future<File> collectionsWithBrokenRows() async {
      final seed = FileLocalMediaCollectionRepository(rootDirectory: root);
      await seed.setFavorite(inRoot('收藏.mp3'), true);
      final playlist = await seed.createPlaylist('夜');
      await seed.addToPlaylist(playlist.id, [inRoot('收藏.mp3')]);
      final store = File(inRoot('library_collections.json'));
      final decoded = jsonDecode(await store.readAsString()) as Map;
      (decoded['favorites'] as List).add(7);
      final playlists = decoded['playlists'] as List;
      playlists
        ..add({'id': 'broken'})
        ..add(Map<String, dynamic>.from(playlists.first as Map));
      await store.writeAsString(jsonEncode(decoded));
      return store;
    }

    test('shows readable favorites and playlists and blocks writes', () async {
      final store = await collectionsWithBrokenRows();
      final original = await store.readAsString();
      final repository = FileLocalMediaCollectionRepository(
        rootDirectory: root,
      );

      expect(await repository.getFavoritePaths(), hasLength(1));
      expect(await repository.getPlaylists(), hasLength(1));
      final issue = await repository.loadIssue();
      expect(issue!.kind, LocalStoreKind.collections);
      // A non-path favorite, an incomplete playlist, and a duplicate id.
      expect(issue.unreadableRecords, 3);

      final playlistId = (await repository.getPlaylists()).single.id;
      for (final write in <Future<Object?> Function()>[
        () => repository.setFavorite(inRoot('new.mp3'), true),
        () => repository.toggleFavorite(inRoot('收藏.mp3')),
        () => repository.createPlaylist('新歌单'),
        () => repository.renamePlaylist(playlistId, '改名'),
        () => repository.deletePlaylist(playlistId),
        () => repository.addToPlaylist(playlistId, [inRoot('new.mp3')]),
        () => repository.removeFromPlaylist(playlistId, inRoot('收藏.mp3')),
      ]) {
        await expectLater(
          write(),
          throwsA(isA<LocalStoreIncompleteException>()),
        );
      }
      expect(await store.readAsString(), original);
      expect(await repository.isFavorite(inRoot('收藏.mp3')), isTrue);
    });

    test('repair preserves the original and announces the change', () async {
      final store = await collectionsWithBrokenRows();
      final original = await store.readAsBytes();
      final repository = FileLocalMediaCollectionRepository(
        rootDirectory: root,
      );
      await repository.getPlaylists();
      final revisions = <int>[];
      final subscription = repository.changes.listen(revisions.add);
      addTearDown(subscription.cancel);

      final result = await repository.repairKeepingReadableRecords();
      await Future<void>.delayed(Duration.zero);

      expect(await File(result.preservedCopyPath).readAsBytes(), original);
      expect(result.droppedRecords, 3);
      expect(revisions, isNotEmpty);
      expect(await repository.setFavorite(inRoot('new.mp3'), true), isTrue);

      final reopened = FileLocalMediaCollectionRepository(rootDirectory: root);
      expect(await reopened.loadIssue(), isNull);
      expect(await reopened.getFavoritePaths(), hasLength(2));
      expect(await reopened.getPlaylists(), hasLength(1));
    });
  });

  group('failed loads are retried on the same instance (#440)', () {
    test('library: invalid file, then fixed file', () async {
      final store = File(inRoot('media_library.json'));
      await store.writeAsString('{not json');
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);
      await expectLater(repository.getAll(), throwsFormatException);
      await expectLater(repository.getRoots(), throwsFormatException);

      final song = await audio('fixed.mp3');
      final seedRoot = await Directory(inRoot('seed')).create();
      final seed = FileLocalMediaLibraryRepository(rootDirectory: seedRoot);
      await seed.addPaths([song.path]);
      await File(
        '${seedRoot.path}${Platform.pathSeparator}media_library.json',
      ).copy(store.path);

      final entries = await repository.getAll();
      expect(entries, hasLength(1));
      expect(entries.single.sourcePath, song.absolute.path);
      expect(await repository.loadIssue(), isNull);
    });

    test('library: unavailable data directory, then created', () async {
      final blocker = File(inRoot('blocker'));
      await blocker.writeAsString('a file where the data folder should be');
      final dataDirectory = Directory(
        '${blocker.path}${Platform.pathSeparator}data',
      );
      final repository = FileLocalMediaLibraryRepository(
        rootDirectory: dataDirectory,
      );
      await expectLater(
        repository.getAll(),
        throwsA(isA<FileSystemException>()),
      );

      await blocker.delete();
      expect(await repository.getAll(), isEmpty);
      final song = await audio('after-fix.mp3');
      expect(await repository.addPaths([song.path]), hasLength(1));
    });

    test('collections: invalid file, then fixed file', () async {
      final store = File(inRoot('library_collections.json'));
      await store.writeAsString('[]');
      final repository = FileLocalMediaCollectionRepository(
        rootDirectory: root,
      );
      await expectLater(repository.getPlaylists(), throwsFormatException);

      await store.writeAsString(
        jsonEncode({
          'version': 1,
          'favorites': [inRoot('fav.mp3')],
          'playlists': <Object>[],
        }),
      );
      expect(await repository.getFavoritePaths(), hasLength(1));
      expect(await repository.setFavorite(inRoot('two.mp3'), true), isTrue);
    });

    test('metadata: invalid file, then fixed file', () async {
      final store = File(inRoot('media_metadata.json'));
      await store.writeAsString('{"version": 1, "items": 3}');
      final repository = FileLocalMediaMetadataRepository(rootDirectory: root);
      await expectLater(repository.getAll(), throwsFormatException);

      final item = LocalMediaMetadata(
        sourcePath: inRoot('song.mp3'),
        title: '修好了',
        updatedAt: DateTime.utc(2026, 11, 14),
      );
      await store.writeAsString(
        jsonEncode({
          'version': 1,
          'items': [item.toJson()],
        }),
      );
      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.title, '修好了');
      final saved = await repository.save(item.copyWith(title: '再保存'));
      expect(saved.title, '再保存');
    });

    test('concurrent callers share one successful load', () async {
      final song = await audio('shared.mp3');
      final seed = FileLocalMediaLibraryRepository(rootDirectory: root);
      await seed.addPaths([song.path]);
      final repository = FileLocalMediaLibraryRepository(rootDirectory: root);

      final results = await Future.wait([
        repository.getAll(),
        repository.getAll(),
        repository.getRoots(),
      ]);
      expect(results[0], hasLength(1));
      expect(results[1], hasLength(1));
      // A shared load must not append the same rows twice.
      expect(await repository.getAll(), hasLength(1));
    });
  });
}
