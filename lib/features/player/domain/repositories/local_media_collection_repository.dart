import 'dart:async';

import '../models/local_playlist.dart';

abstract class LocalMediaCollectionRepository {
  /// Emits after any persisted favorites/playlist mutation.
  Stream<int> get changes;

  Future<Set<String>> getFavoritePaths();

  Future<bool> isFavorite(String sourcePath);

  /// Persists the requested favorite state and returns the resulting state.
  Future<bool> setFavorite(String sourcePath, bool favorite);

  Future<bool> toggleFavorite(String sourcePath);

  Future<List<LocalPlaylist>> getPlaylists();

  Future<LocalPlaylist> createPlaylist(
    String name, {
    String? description,
  });

  Future<LocalPlaylist> renamePlaylist(String playlistId, String name);

  Future<void> deletePlaylist(String playlistId);

  Future<LocalPlaylist> addToPlaylist(
    String playlistId,
    Iterable<String> sourcePaths,
  );

  Future<LocalPlaylist> removeFromPlaylist(
    String playlistId,
    String sourcePath,
  );

  Future<LocalPlaylist> moveInPlaylist(
    String playlistId,
    int oldIndex,
    int newIndex,
  );
}
