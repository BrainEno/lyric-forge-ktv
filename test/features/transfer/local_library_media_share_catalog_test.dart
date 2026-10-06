import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/local_library_media_share_catalog.dart';

void main() {
  test('build exposes playable desktop library entries and filters missing files',
      () async {
    final directory = await Directory.systemTemp.createTemp('lyricforge-share-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final playable = File('${directory.path}${Platform.pathSeparator}song.mp3');
    await playable.writeAsBytes(List<int>.filled(2048, 7));
    final now = DateTime(2026, 10, 6);

    final repository = _FakeLibraryRepository([
      LocalMediaLibraryEntry(
        sourcePath: playable.path,
        format: 'mp3',
        addedAt: now,
        lastSeenAt: now,
        embeddedTitle: 'Desktop Song',
        embeddedArtist: 'Test Artist',
        embeddedAlbum: 'Test Album',
        durationMs: 123000,
        sourceSizeBytes: 2048,
      ),
      LocalMediaLibraryEntry(
        sourcePath: '${directory.path}${Platform.pathSeparator}missing.flac',
        format: 'flac',
        addedAt: now,
        lastSeenAt: now,
        isMissing: true,
      ),
    ]);

    final catalog = LocalLibraryMediaShareCatalog(
      libraryRepository: repository,
    );
    final tracks = await catalog.build();

    expect(tracks, hasLength(1));
    expect(tracks.single.title, 'Desktop Song');
    expect(tracks.single.artist, 'Test Artist');
    expect(tracks.single.album, 'Test Album');
    expect(tracks.single.format, 'mp3');
    expect(tracks.single.byteLength, 2048);
    expect(tracks.single.duration, const Duration(seconds: 123));
    expect(tracks.single.localPath, playable.path);
    expect(tracks.single.id, startsWith('library-'));
  });

  test('build falls back to file name and actual byte length', () async {
    final directory = await Directory.systemTemp.createTemp('lyricforge-share-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final playable = File('${directory.path}${Platform.pathSeparator}No Tags.wav');
    await playable.writeAsBytes(List<int>.filled(321, 1));
    final now = DateTime(2026, 10, 6);
    final repository = _FakeLibraryRepository([
      LocalMediaLibraryEntry(
        sourcePath: playable.path,
        format: '',
        addedAt: now,
        lastSeenAt: now,
      ),
    ]);

    final tracks = await LocalLibraryMediaShareCatalog(
      libraryRepository: repository,
    ).build();

    expect(tracks.single.title, 'No Tags');
    expect(tracks.single.format, 'wav');
    expect(tracks.single.byteLength, 321);
  });
}

class _FakeLibraryRepository implements LocalMediaLibraryRepository {
  final List<LocalMediaLibraryEntry> entries;

  _FakeLibraryRepository(this.entries);

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => List.of(entries);

  @override
  Future<LocalMediaLibraryEntry?> getByPath(String sourcePath) async {
    for (final entry in entries) {
      if (entry.sourcePath == sourcePath) return entry;
    }
    return null;
  }

  @override
  Future<List<LocalMediaLibraryEntry>> addPaths(Iterable<String> paths) async =>
      List.of(entries);

  @override
  Future<List<String>> getRoots() async => const [];

  @override
  Future<void> addRoot(String rootPath) async {}

  @override
  Future<List<LocalMediaLibraryEntry>> refreshAvailability() async =>
      List.of(entries);

  @override
  Future<List<LocalMediaLibraryEntry>> refreshFromRoots(
    Iterable<String> supportedExtensions,
  ) async =>
      List.of(entries);

  @override
  Future<List<LocalMediaLibraryEntry>> refreshMetadata({bool force = false}) async =>
      List.of(entries);

  @override
  Future<void> remove(String sourcePath) async {}

  @override
  Future<void> removeMissing() async {}
}
