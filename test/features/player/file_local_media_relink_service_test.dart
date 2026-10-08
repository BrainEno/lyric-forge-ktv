import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_local_media_relink_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
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
    await collections.addToPlaylist(
      playlist.id,
      [before.path, oldFile.path, after.path],
    );
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
}
