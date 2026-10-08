import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/local_media_relink_service.dart';
import '../repositories/file_play_history_repository.dart';

class FileLocalMediaRelinkService implements LocalMediaRelinkService {
  final LocalMediaLibraryRepository libraryRepository;
  final LocalMediaCollectionRepository collectionRepository;
  final LocalMediaMetadataRepository metadataRepository;
  final FilePlayHistoryRepository historyRepository;
  final List<String> supportedExtensions;

  const FileLocalMediaRelinkService({
    required this.libraryRepository,
    required this.collectionRepository,
    required this.metadataRepository,
    required this.historyRepository,
    required this.supportedExtensions,
  });

  String _pathKey(String path) {
    final absolute = File(path).absolute.path;
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  bool _isSupported(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return supportedExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  @override
  Future<LocalMediaRelinkResult?> pickReplacementAndRelink(
    String oldPath,
  ) async {
    final useUnfilteredMacPicker = Platform.isMacOS;
    final result = await FilePicker.platform.pickFiles(
      type: useUnfilteredMacPicker ? FileType.any : FileType.custom,
      allowedExtensions: useUnfilteredMacPicker ? null : supportedExtensions,
      allowMultiple: false,
      dialogTitle: '重新定位音频文件',
      allowCompression: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null || path.trim().isEmpty) return null;
    return relink(oldPath: oldPath, newPath: path);
  }

  @override
  Future<LocalMediaRelinkResult> relink({
    required String oldPath,
    required String newPath,
  }) async {
    final oldAbsolute = File(oldPath).absolute.path;
    final newFile = File(newPath);
    final newAbsolute = newFile.absolute.path;

    if (_pathKey(oldAbsolute) == _pathKey(newAbsolute)) {
      throw ArgumentError('新文件路径与旧路径相同');
    }
    if (!await newFile.exists()) {
      throw FileSystemException('重新定位的音频文件不存在', newPath);
    }
    if (!_isSupported(newAbsolute)) {
      throw UnsupportedError('不支持的音频格式：$newAbsolute');
    }

    final oldEntry = await libraryRepository.getByPath(oldAbsolute);
    if (oldEntry == null) {
      throw StateError('音乐库中找不到需要重新定位的条目');
    }

    // Add the replacement first. The old missing library row is removed only
    // after every related store has migrated successfully, so a failed relink
    // never starts by deleting the user's existing reference.
    await libraryRepository.addPaths([newAbsolute]);
    final replacement = await libraryRepository.getByPath(newAbsolute);
    if (replacement == null || replacement.isMissing) {
      throw StateError('新音频文件无法加入音乐库');
    }

    final oldMetadata = await metadataRepository.getForAudio(oldAbsolute);
    var metadataMigrated = false;
    if (oldMetadata != null) {
      await metadataRepository.save(
        oldMetadata.copyWith(sourcePath: newAbsolute),
      );
      await metadataRepository.removeForAudio(oldAbsolute);
      metadataMigrated = true;
    }

    final historyMigrated = await historyRepository.replaceLocalPath(
      oldPath: oldAbsolute,
      newPath: newAbsolute,
    );

    final favoriteMigrated = await collectionRepository.isFavorite(oldAbsolute);
    if (favoriteMigrated) {
      await collectionRepository.setFavorite(newAbsolute, true);
      await collectionRepository.setFavorite(oldAbsolute, false);
    }

    var playlistsMigrated = 0;
    final playlists = await collectionRepository.getPlaylists();
    for (final playlist in playlists) {
      final oldIndex = playlist.sourcePaths.indexWhere(
        (path) => _pathKey(path) == _pathKey(oldAbsolute),
      );
      if (oldIndex < 0) continue;

      final alreadyContainsNew = playlist.sourcePaths.any(
        (path) => _pathKey(path) == _pathKey(newAbsolute),
      );
      if (!alreadyContainsNew) {
        await collectionRepository.addToPlaylist(
          playlist.id,
          [newAbsolute],
        );
      }
      var updated = await collectionRepository.removeFromPlaylist(
        playlist.id,
        oldAbsolute,
      );

      if (!alreadyContainsNew && updated.sourcePaths.isNotEmpty) {
        final currentIndex = updated.sourcePaths.indexWhere(
          (path) => _pathKey(path) == _pathKey(newAbsolute),
        );
        var targetIndex = oldIndex;
        if (targetIndex >= updated.sourcePaths.length) {
          targetIndex = updated.sourcePaths.length - 1;
        }
        if (currentIndex >= 0 && currentIndex != targetIndex) {
          updated = await collectionRepository.moveInPlaylist(
            playlist.id,
            currentIndex,
            targetIndex,
          );
        }
      }
      playlistsMigrated += 1;
    }

    await libraryRepository.remove(oldAbsolute);

    return LocalMediaRelinkResult(
      oldPath: oldAbsolute,
      newPath: newAbsolute,
      favoriteMigrated: favoriteMigrated,
      playlistsMigrated: playlistsMigrated,
      metadataMigrated: metadataMigrated,
      historyMigrated: historyMigrated,
    );
  }
}
