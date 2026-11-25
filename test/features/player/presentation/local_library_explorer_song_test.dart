import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/presentation/local_library_explorer_song.dart';

void main() {
  test('keeps metadata and missing library references', () {
    final now = DateTime(2026);
    final path = '${Directory.systemTemp.path}/missing-explorer-song.mp3';
    final song = LocalLibraryExplorerSong(
      entry: LocalMediaLibraryEntry(
        sourcePath: path,
        format: 'mp3',
        addedAt: now,
        lastSeenAt: now,
        embeddedTitle: 'Embedded title',
        embeddedArtist: 'Embedded artist',
      ),
      override: LocalMediaMetadata(
        sourcePath: path,
        title: 'Edited title',
        artist: 'Edited artist',
        updatedAt: now,
        metadata: const {'linkedProjectId': 'project'},
      ),
      lastPlayedAt: now,
      playlistNames: const ['Favorites'],
    );

    expect(song.title, 'Edited title');
    expect(song.artist, 'Edited artist');
    expect(song.hasLyrics, isTrue);
    expect(song.playable, isFalse);
    expect(song.playbackItem.audioAsset.originalPath, path);
    expect(song.browseItem.lastPlayedAt, now);
    expect(song.browseItem.playlistNames, ['Favorites']);
    expect(song.secondary, 'Edited artist · MP3');
  });

  test('maps a playable song to an original-source queue item', () async {
    final directory = await Directory.systemTemp.createTemp(
      'local-library-explorer-song-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/song.mp3');
    await file.writeAsBytes([1, 2, 3]);
    final now = DateTime(2026);
    final song = LocalLibraryExplorerSong(
      entry: LocalMediaLibraryEntry(
        sourcePath: file.path,
        format: 'mp3',
        addedAt: now,
        lastSeenAt: now,
        embeddedTitle: 'Embedded title',
      ),
      override: LocalMediaMetadata(
        sourcePath: file.path,
        title: 'Edited title',
        updatedAt: now,
      ),
      lastPlayedAt: null,
      playlistNames: const [],
    );

    final item = song.playbackItem;

    expect(item, isNotNull);
    expect(item.id, 'local:${file.path}');
    expect(item.title, 'Edited title');
    expect(item.audioAsset.originalPath, file.path);
    expect(item.preferredSource.name, 'original');
  });
}
