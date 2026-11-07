import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';

void main() {
  group('FileLocalMediaMetadataRepository', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'lyricforge-media-meta-',
      );
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('persists Chinese Japanese and emoji overrides as UTF-8', () async {
      final audio = File(
        '${directory.path}${Platform.pathSeparator}原曲_日本語🎵.flac',
      );
      await audio.writeAsBytes([1, 2, 3]);
      final repository = FileLocalMediaMetadataRepository(
        rootDirectory: directory,
      );

      await repository.save(
        LocalMediaMetadata(
          sourcePath: audio.path,
          title: '夜に駆ける / 夜曲 🎵',
          artist: 'ヨルシカ・周杰伦',
          album: '本地收藏「测试」',
          updatedAt: DateTime(2026, 10, 4),
        ),
      );

      final restored = FileLocalMediaMetadataRepository(
        rootDirectory: directory,
      );
      final value = await restored.getForAudio(audio.path);
      expect(value, isNotNull);
      expect(value!.title, '夜に駆ける / 夜曲 🎵');
      expect(value.artist, 'ヨルシカ・周杰伦');
      expect(value.album, '本地收藏「测试」');

      final jsonFile = File(
        '${directory.path}${Platform.pathSeparator}media_metadata.json',
      );
      final raw = await jsonFile.readAsString(encoding: utf8);
      expect(raw, contains('夜に駆ける / 夜曲 🎵'));
      expect(raw, contains('ヨルシカ・周杰伦'));
    });

    test('same source path replaces the previous override', () async {
      final audio = File('${directory.path}${Platform.pathSeparator}song.mp3');
      await audio.writeAsBytes([1]);
      final repository = FileLocalMediaMetadataRepository(
        rootDirectory: directory,
      );

      await repository.save(
        LocalMediaMetadata(
          sourcePath: audio.path,
          title: 'Old title',
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await repository.save(
        LocalMediaMetadata(
          sourcePath: audio.path,
          title: '新しい名前',
          updatedAt: DateTime(2026, 1, 2),
        ),
      );

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.title, '新しい名前');
    });

    for (final corrupt in <String, Object>{
      'non-object': 'corrupt',
      'invalid date': {'sourcePath': '/broken.mp3', 'updatedAt': 'bad'},
      'invalid metadata': {
        'sourcePath': '/broken.mp3',
        'updatedAt': '2026-01-01T00:00:00.000',
        'metadata': 'not an object',
      },
    }.entries) {
      test(
        'partial load blocks writes without losing records: ${corrupt.key}',
        () async {
          final file = File(
            '${directory.path}${Platform.pathSeparator}media_metadata.json',
          );
          final backup = File('${file.path}.bak');
          final valid = LocalMediaMetadata(
            sourcePath: '${directory.path}${Platform.pathSeparator}song.mp3',
            title: '用户标题',
            updatedAt: DateTime(2026),
            metadata: const {'linkedProjectId': 'project-1', 'hasLyrics': true},
          );
          final original = jsonEncode({
            'version': 1,
            'items': [valid.toJson(), corrupt.value],
          });
          final oldBackup = jsonEncode({'version': 1, 'items': []});
          await file.writeAsString(original, flush: true);
          await backup.writeAsString(oldBackup, flush: true);
          final repository = FileLocalMediaMetadataRepository(
            rootDirectory: directory,
          );

          final values = await repository.getAll();
          expect(values, hasLength(1));
          expect(values.single.title, '用户标题');
          expect(values.single.metadata['linkedProjectId'], 'project-1');
          await expectLater(repository.getCompleteForAudio(valid.sourcePath), throwsFormatException);
          await expectLater(repository.getCompleteForAudio('/absent.mp3'), throwsFormatException);
          await expectLater(
            repository.save(valid.copyWith(title: 'overwrite')),
            throwsFormatException,
          );
          await expectLater(
            repository.removeForAudio(valid.sourcePath),
            throwsFormatException,
          );
          await expectLater(
            repository.removeForAudio('/absent.mp3'),
            throwsFormatException,
          );
          expect(
            (await repository.getForAudio(valid.sourcePath))?.title,
            '用户标题',
          );
          expect(await file.readAsString(), original);
          expect(await backup.readAsString(), oldBackup);
          expect(await File('${file.path}.tmp').exists(), isFalse);

          // A deliberate external repair can be read by a new repository instance.
          await file.writeAsString(
            jsonEncode({
              'version': 1,
              'items': [valid.toJson()],
            }),
          );
          final repaired = FileLocalMediaMetadataRepository(
            rootDirectory: directory,
          );
          expect((await repaired.getCompleteForAudio(valid.sourcePath))?.metadata['linkedProjectId'], 'project-1');
          expect(await repaired.getCompleteForAudio('/absent.mp3'), isNull);
          await repaired.save(valid.copyWith(title: 'after repair'));
          expect(
            (await repaired.getForAudio(valid.sourcePath))?.title,
            'after repair',
          );
        },
      );
    }

    test('duplicate canonical paths remain readable for display but block associations and writes', () async {
      final file = File('${directory.path}${Platform.pathSeparator}media_metadata.json');
      final source = '${directory.path}${Platform.pathSeparator}song.mp3';
      final first = LocalMediaMetadata(sourcePath: source, title: 'first', updatedAt: DateTime(2026), metadata: const {'linkedProjectId': 'original'});
      final second = first.copyWith(title: 'second', metadata: const {'linkedProjectId': 'other'});
      final original = jsonEncode({'items': [first.toJson(), second.toJson()]});
      final backup = File('${file.path}.bak');
      const oldBackup = '{"items":[]}';
      await file.writeAsString(original);
      await backup.writeAsString(oldBackup);
      final repository = FileLocalMediaMetadataRepository(rootDirectory: directory);

      expect((await repository.getForAudio(source))?.title, 'second');
      await expectLater(repository.getCompleteForAudio(source), throwsFormatException);
      await expectLater(repository.getCompleteForAudio('/absent.mp3'), throwsFormatException);
      await expectLater(repository.save(first), throwsFormatException);
      await expectLater(repository.removeForAudio(source), throwsFormatException);
      expect(await file.readAsString(), original);
      expect(await backup.readAsString(), oldBackup);
    });

    test(
      'partial load protects managed artwork from replacement and deletion',
      () async {
        final sourcePath = '${directory.path}${Platform.pathSeparator}song.mp3';
        final firstImage = File(
          '${directory.path}${Platform.pathSeparator}first.png',
        );
        final secondImage = File(
          '${directory.path}${Platform.pathSeparator}second.png',
        );
        await firstImage.writeAsBytes([1, 2, 3]);
        await secondImage.writeAsBytes([4, 5, 6]);
        final seed = FileLocalMediaMetadataRepository(rootDirectory: directory);
        final artworkPath = await seed.importArtwork(
          sourcePath: sourcePath,
          imagePath: firstImage.path,
        );
        final file = File(
          '${directory.path}${Platform.pathSeparator}media_metadata.json',
        );
        final original = jsonEncode({
          'version': 1,
          'items': [
            LocalMediaMetadata(
              sourcePath: sourcePath,
              artworkPath: artworkPath,
              updatedAt: DateTime(2026),
            ).toJson(),
            'broken',
          ],
        });
        await file.writeAsString(original);
        final repository = FileLocalMediaMetadataRepository(
          rootDirectory: directory,
        );

        await expectLater(
          repository.removeManagedArtwork(artworkPath),
          throwsFormatException,
        );
        await expectLater(
          repository.importArtwork(
            sourcePath: sourcePath,
            imagePath: secondImage.path,
          ),
          throwsFormatException,
        );
        expect(await File(artworkPath).readAsBytes(), [1, 2, 3]);
        expect(await File('$artworkPath.tmp').exists(), isFalse);
        expect(await file.readAsString(), original);
      },
    );

    test('legacy entries without metadata remain writable', () async {
      final file = File(
        '${directory.path}${Platform.pathSeparator}media_metadata.json',
      );
      final sourcePath = '${directory.path}${Platform.pathSeparator}legacy.mp3';
      await file.writeAsString(
        jsonEncode({
          'items': [
            {'sourcePath': sourcePath, 'updatedAt': '2026-01-01T00:00:00.000'},
          ],
        }),
      );
      final repository = FileLocalMediaMetadataRepository(
        rootDirectory: directory,
      );
      final entry = await repository.getForAudio(sourcePath);
      expect(entry, isNotNull);
      expect(entry!.metadata, isEmpty);
      await repository.save(entry.copyWith(title: 'legacy updated'));
      expect(
        (await repository.getForAudio(sourcePath))?.title,
        'legacy updated',
      );
    });

    test('imports artwork into app-owned MediaArtwork storage', () async {
      final audio = File('${directory.path}${Platform.pathSeparator}song.mp3');
      final image = File('${directory.path}${Platform.pathSeparator}封面.png');
      await audio.writeAsBytes([1]);
      await image.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);
      final repository = FileLocalMediaMetadataRepository(
        rootDirectory: directory,
      );

      final imported = await repository.importArtwork(
        sourcePath: audio.path,
        imagePath: image.path,
      );

      expect(await File(imported).exists(), isTrue);
      expect(File(imported).parent.path, contains('MediaArtwork'));
      expect(imported.toLowerCase(), endsWith('.png'));
    });

    test('does not delete an arbitrary external artwork file', () async {
      final image = File(
        '${directory.path}${Platform.pathSeparator}outside.jpg',
      );
      await image.writeAsBytes([1, 2, 3]);
      final repository = FileLocalMediaMetadataRepository(
        rootDirectory: directory,
      );

      await repository.removeManagedArtwork(image.path);

      expect(await image.exists(), isTrue);
    });
  });
}
