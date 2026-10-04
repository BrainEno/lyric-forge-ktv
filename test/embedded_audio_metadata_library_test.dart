import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/embedded_audio_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/embedded_audio_metadata_reader.dart';

class _FakeEmbeddedReader implements EmbeddedAudioMetadataReader {
  int calls = 0;

  @override
  Future<EmbeddedAudioMetadata> read(String sourcePath) async {
    calls += 1;
    final file = File(sourcePath);
    final stat = await file.stat();
    return EmbeddedAudioMetadata(
      sourcePath: file.absolute.path,
      title: '中文标题 $calls',
      artist: '宇多田ヒカル',
      album: 'First Love',
      artworkPath: '${file.parent.path}${Platform.pathSeparator}cover-$calls.jpg',
      genres: const ['J-Pop'],
      trackNumber: 3,
      year: 1999,
      duration: const Duration(minutes: 4, seconds: 17),
      sourceSizeBytes: stat.size,
      sourceModifiedAt: stat.modified,
      scannedAt: DateTime.now(),
    );
  }
}

void main() {
  test('reads and persists embedded metadata for a new library song', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-tags-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}曲.mp3');
    await audio.writeAsBytes(const [1, 2, 3]);
    final reader = _FakeEmbeddedReader();
    final repository = FileLocalMediaLibraryRepository(
      rootDirectory: root,
      metadataReader: reader,
    );

    await repository.addPaths([audio.path]);
    final entry = (await repository.getAll()).single;

    expect(reader.calls, 1);
    expect(entry.embeddedTitle, '中文标题 1');
    expect(entry.embeddedArtist, '宇多田ヒカル');
    expect(entry.embeddedAlbum, 'First Love');
    expect(entry.embeddedGenres, const ['J-Pop']);
    expect(entry.embeddedTrackNumber, 3);
    expect(entry.embeddedYear, 1999);
    expect(entry.durationMs, const Duration(minutes: 4, seconds: 17).inMilliseconds);
    expect(entry.metadataScannedAt, isNotNull);

    final restored = FileLocalMediaLibraryRepository(rootDirectory: root);
    final restoredEntry = (await restored.getAll()).single;
    expect(restoredEntry.embeddedTitle, '中文标题 1');
    expect(restoredEntry.embeddedArtist, '宇多田ヒカル');
    expect(restoredEntry.embeddedAlbum, 'First Love');
  });

  test('unchanged source file reuses cached embedded metadata', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-tags-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}song.flac');
    await audio.writeAsBytes(const [1, 2, 3]);
    final reader = _FakeEmbeddedReader();
    final repository = FileLocalMediaLibraryRepository(
      rootDirectory: root,
      metadataReader: reader,
    );

    await repository.addPaths([audio.path]);
    await repository.addPaths([audio.path]);
    await repository.refreshMetadata();

    expect(reader.calls, 1);
    expect((await repository.getAll()).single.embeddedTitle, '中文标题 1');
  });

  test('source file change invalidates metadata fingerprint', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-tags-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}song.m4a');
    await audio.writeAsBytes(const [1]);
    final reader = _FakeEmbeddedReader();
    final repository = FileLocalMediaLibraryRepository(
      rootDirectory: root,
      metadataReader: reader,
    );

    await repository.addPaths([audio.path]);
    await audio.writeAsBytes(const [1, 2, 3, 4], flush: true);
    await repository.refreshMetadata();

    expect(reader.calls, 2);
    expect((await repository.getAll()).single.embeddedTitle, '中文标题 2');
  });

  test('forced metadata refresh ignores an unchanged source fingerprint', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-tags-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final audio = File('${root.path}${Platform.pathSeparator}song.wav');
    await audio.writeAsBytes(const [1, 2]);
    final reader = _FakeEmbeddedReader();
    final repository = FileLocalMediaLibraryRepository(
      rootDirectory: root,
      metadataReader: reader,
    );

    await repository.addPaths([audio.path]);
    await repository.refreshMetadata(force: true);

    expect(reader.calls, 2);
    expect((await repository.getAll()).single.embeddedTitle, '中文标题 2');
  });
}
