import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';

void main() {
  group('FileLocalMediaMetadataRepository', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lyricforge-media-meta-');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('persists Chinese Japanese and emoji overrides as UTF-8', () async {
      final audio = File('${directory.path}${Platform.pathSeparator}原曲_日本語🎵.flac');
      await audio.writeAsBytes([1, 2, 3]);
      final repository = FileLocalMediaMetadataRepository(rootDirectory: directory);

      await repository.save(
        LocalMediaMetadata(
          sourcePath: audio.path,
          title: '夜に駆ける / 夜曲 🎵',
          artist: 'ヨルシカ・周杰伦',
          album: '本地收藏「测试」',
          updatedAt: DateTime(2026, 10, 4),
        ),
      );

      final restored = FileLocalMediaMetadataRepository(rootDirectory: directory);
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
      final repository = FileLocalMediaMetadataRepository(rootDirectory: directory);

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

    test('imports artwork into app-owned MediaArtwork storage', () async {
      final audio = File('${directory.path}${Platform.pathSeparator}song.mp3');
      final image = File('${directory.path}${Platform.pathSeparator}封面.png');
      await audio.writeAsBytes([1]);
      await image.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);
      final repository = FileLocalMediaMetadataRepository(rootDirectory: directory);

      final imported = await repository.importArtwork(
        sourcePath: audio.path,
        imagePath: image.path,
      );

      expect(await File(imported).exists(), isTrue);
      expect(File(imported).parent.path, contains('MediaArtwork'));
      expect(imported.toLowerCase(), endsWith('.png'));
    });

    test('does not delete an arbitrary external artwork file', () async {
      final image = File('${directory.path}${Platform.pathSeparator}outside.jpg');
      await image.writeAsBytes([1, 2, 3]);
      final repository = FileLocalMediaMetadataRepository(rootDirectory: directory);

      await repository.removeManagedArtwork(image.path);

      expect(await image.exists(), isTrue);
    });
  });
}
