import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_playlist.dart';

void main() {
  group('file-backed local media repositories recover safely', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'lyricforge-safe-load-',
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    group('library', () {
      test(
        'rejects a malformed row, preserves canonical and backup documents, then retries after repair',
        () async {
          final store = _store(directory, 'media_library.json');
          final backup = File('${store.path}.bak');
          final firstPath = _mediaPath(directory, '保留的歌.mp3');
          final secondFile = File(_mediaPath(directory, '新歌.flac'));
          await secondFile.writeAsBytes([1, 2, 3]);
          final original = jsonEncode({
            'version': 3,
            'roots': [directory.path],
            'entries': [_libraryEntry(firstPath).toJson(), 'broken row'],
          });
          const backupContents = '{"version":3,"roots":[],"entries":[]}';
          await store.writeAsString(original, flush: true);
          await backup.writeAsString(backupContents, flush: true);
          final repository = FileLocalMediaLibraryRepository(
            rootDirectory: directory,
          );

          await expectLater(repository.getAll(), throwsFormatException);
          await expectLater(repository.getRoots(), throwsFormatException);
          await expectLater(
            repository.addPaths([secondFile.path]),
            throwsFormatException,
          );
          await expectLater(
            repository.remove(firstPath),
            throwsFormatException,
          );
          expect(await store.readAsString(), original);
          expect(await backup.readAsString(), backupContents);
          expect(await File('${store.path}.tmp').exists(), isFalse);

          await _writeJson(store, {
            'version': 3,
            'roots': [directory.path],
            'entries': [_libraryEntry(firstPath).toJson()],
          });
          expect((await repository.getAll()).single.sourcePath, firstPath);
          await repository.addPaths([secondFile.path]);

          final recreated = FileLocalMediaLibraryRepository(
            rootDirectory: directory,
          );
          final paths = (await recreated.getAll())
              .map((entry) => entry.sourcePath)
              .toSet();
          expect(paths, {firstPath, secondFile.absolute.path});
          expect(await recreated.getRoots(), [directory.absolute.path]);
        },
      );

      for (final invalid in <String, Map<String, Object>>{
        'duplicate canonical entry': {
          'version': 3,
          'entries': [
            _libraryEntry('/music/duplicate.mp3').toJson(),
            _libraryEntry('/music/duplicate.mp3').toJson(),
          ],
        },
        'invalid root': {
          'version': 3,
          'roots': [''],
          'entries': [],
        },
        'duplicate root': {
          'version': 3,
          'roots': ['/music', '/music'],
          'entries': [],
        },
      }.entries) {
        test('does not normalize away an invalid $invalid', () async {
          final store = _store(directory, 'media_library.json');
          final original = jsonEncode(invalid.value);
          await store.writeAsString(original, flush: true);
          final repository = FileLocalMediaLibraryRepository(
            rootDirectory: directory,
          );

          await expectLater(repository.getAll(), throwsFormatException);
          await expectLater(
            repository.addRoot('/another-root'),
            throwsFormatException,
          );
          expect(await store.readAsString(), original);
        });
      }

      test(
        'shares a transient failed restore and succeeds on the same instance after the root is repaired',
        () async {
          final blockedPath =
              '${directory.path}${Platform.pathSeparator}blocked-library';
          final blockedFile = File(blockedPath);
          await blockedFile.writeAsString('not a directory');
          final repository = FileLocalMediaLibraryRepository(
            rootDirectory: Directory(blockedPath),
          );

          final first = repository.getAll();
          final second = repository.getRoots();
          await expectLater(first, throwsA(isA<FileSystemException>()));
          await expectLater(second, throwsA(isA<FileSystemException>()));

          await blockedFile.delete();
          await Directory(blockedPath).create();
          expect(await repository.getAll(), isEmpty);
          await repository.addRoot(directory.path);
          expect(await repository.getRoots(), [directory.absolute.path]);
        },
      );
    });

    group('collections', () {
      test(
        'rejects one malformed playlist without overwriting favorites or valid playlists',
        () async {
          final store = _store(directory, 'library_collections.json');
          final backup = File('${store.path}.bak');
          final favorite = _mediaPath(directory, 'favorite.mp3');
          final playlist = _playlist(
            id: 'preserve',
            name: '保留歌单',
            sourcePaths: [_mediaPath(directory, 'first.mp3')],
          );
          final original = jsonEncode({
            'version': 1,
            'favorites': [favorite],
            'playlists': [
              playlist.toJson(),
              {'id': 'broken'},
            ],
          });
          const backupContents = '{"version":1,"favorites":[],"playlists":[]}';
          await store.writeAsString(original, flush: true);
          await backup.writeAsString(backupContents, flush: true);
          final repository = FileLocalMediaCollectionRepository(
            rootDirectory: directory,
          );

          await expectLater(
            repository.getFavoritePaths(),
            throwsFormatException,
          );
          await expectLater(repository.getPlaylists(), throwsFormatException);
          await expectLater(
            repository.setFavorite('/new.mp3', true),
            throwsFormatException,
          );
          await expectLater(
            repository.createPlaylist('不会写入'),
            throwsFormatException,
          );
          expect(await store.readAsString(), original);
          expect(await backup.readAsString(), backupContents);

          await _writeJson(store, {
            'version': 1,
            'favorites': [favorite],
            'playlists': [playlist.toJson()],
          });
          expect(await repository.getFavoritePaths(), {
            File(favorite).absolute.path,
          });
          expect((await repository.getPlaylists()).single.name, '保留歌单');
          await repository.setFavorite(_mediaPath(directory, 'new.mp3'), true);

          final recreated = FileLocalMediaCollectionRepository(
            rootDirectory: directory,
          );
          expect(await recreated.getFavoritePaths(), hasLength(2));
          expect((await recreated.getPlaylists()).single.sourcePaths, [
            File(playlist.sourcePaths.single).absolute.path,
          ]);
        },
      );

      for (final invalid in <String, Map<String, Object>>{
        'duplicate favorite': {
          'version': 1,
          'favorites': ['/music/favorite.mp3', '/music/favorite.mp3'],
          'playlists': [],
        },
        'duplicate playlist ID': {
          'version': 1,
          'favorites': [],
          'playlists': [
            _playlist(id: 'same', name: '甲').toJson(),
            _playlist(id: 'same', name: '乙').toJson(),
          ],
        },
        'duplicate playlist member': {
          'version': 1,
          'favorites': [],
          'playlists': [
            _playlist(
              id: 'same',
              name: '重复成员',
              sourcePaths: ['/music/song.mp3', '/music/song.mp3'],
            ).toJson(),
          ],
        },
      }.entries) {
        test('does not silently deduplicate $invalid', () async {
          final store = _store(directory, 'library_collections.json');
          final original = jsonEncode(invalid.value);
          await store.writeAsString(original, flush: true);
          final repository = FileLocalMediaCollectionRepository(
            rootDirectory: directory,
          );

          await expectLater(repository.getPlaylists(), throwsFormatException);
          await expectLater(
            repository.setFavorite('/new.mp3', true),
            throwsFormatException,
          );
          expect(await store.readAsString(), original);
        });
      }

      test(
        'retries a transient storage failure with the same collection repository',
        () async {
          final blockedPath =
              '${directory.path}${Platform.pathSeparator}blocked-collections';
          final blockedFile = File(blockedPath);
          await blockedFile.writeAsString('not a directory');
          final repository = FileLocalMediaCollectionRepository(
            rootDirectory: Directory(blockedPath),
          );

          final first = repository.getFavoritePaths();
          final second = repository.getPlaylists();
          await expectLater(first, throwsA(isA<FileSystemException>()));
          await expectLater(second, throwsA(isA<FileSystemException>()));

          await blockedFile.delete();
          await Directory(blockedPath).create();
          expect(await repository.getFavoritePaths(), isEmpty);
          expect(await repository.getPlaylists(), isEmpty);
          final created = await repository.createPlaylist('修复后可用');
          expect(created.name, '修复后可用');
        },
      );
    });

    group('metadata', () {
      test(
        're-reads a partial display snapshot on the same instance after an external repair',
        () async {
          final store = _store(directory, 'media_metadata.json');
          final firstPath = _mediaPath(directory, 'before.mp3');
          final repairedPath = _mediaPath(directory, 'after.mp3');
          final original = jsonEncode({
            'version': 1,
            'items': [
              _metadata(firstPath, '旧显示标题').toJson(),
              'broken metadata row',
            ],
          });
          await store.writeAsString(original, flush: true);
          final repository = FileLocalMediaMetadataRepository(
            rootDirectory: directory,
          );

          expect((await repository.getAll()).single.title, '旧显示标题');
          await expectLater(
            repository.getCompleteForAudio(firstPath),
            throwsFormatException,
          );
          await expectLater(
            repository.save(_metadata(firstPath, '不能覆盖')),
            throwsFormatException,
          );
          expect(await store.readAsString(), original);

          await _writeJson(store, {
            'version': 1,
            'items': [_metadata(repairedPath, '修复后的标题').toJson()],
          });
          final repaired = await repository.getCompleteForAudio(repairedPath);
          expect(repaired?.title, '修复后的标题');
          expect(await repository.getForAudio(firstPath), isNull);
          await repository.save(_metadata(repairedPath, '已保存'));
          expect(
            (await repository.getCompleteForAudio(repairedPath))?.title,
            '已保存',
          );
        },
      );

      test(
        'forgets a failed metadata Future so the same instance can load after path repair',
        () async {
          final blockedPath =
              '${directory.path}${Platform.pathSeparator}blocked-metadata';
          final blockedFile = File(blockedPath);
          await blockedFile.writeAsString('not a directory');
          final repository = FileLocalMediaMetadataRepository(
            rootDirectory: Directory(blockedPath),
          );

          final first = repository.getAll();
          final second = repository.getForAudio('/nothing.mp3');
          await expectLater(first, throwsA(isA<FileSystemException>()));
          await expectLater(second, throwsA(isA<FileSystemException>()));

          await blockedFile.delete();
          await Directory(blockedPath).create();
          expect(await repository.getAll(), isEmpty);
          final source = _mediaPath(directory, 'saved-after-retry.mp3');
          await repository.save(_metadata(source, '恢复成功'));
          expect((await repository.getForAudio(source))?.title, '恢复成功');
        },
      );
    });
  });
}

File _store(Directory directory, String name) =>
    File('${directory.path}${Platform.pathSeparator}$name');

String _mediaPath(Directory directory, String name) =>
    '${directory.path}${Platform.pathSeparator}$name';

Future<void> _writeJson(File file, Object value) =>
    file.writeAsString(jsonEncode(value), flush: true);

LocalMediaLibraryEntry _libraryEntry(String sourcePath) =>
    LocalMediaLibraryEntry(
      sourcePath: sourcePath,
      format: 'mp3',
      addedAt: DateTime.utc(2026, 1, 1),
      lastSeenAt: DateTime.utc(2026, 1, 1),
    );

LocalPlaylist _playlist({
  required String id,
  required String name,
  List<String> sourcePaths = const [],
}) => LocalPlaylist(
  id: id,
  name: name,
  sourcePaths: sourcePaths,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

LocalMediaMetadata _metadata(String sourcePath, String title) =>
    LocalMediaMetadata(
      sourcePath: sourcePath,
      title: title,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
