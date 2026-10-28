class LocalMediaRelinkResult {
  final String oldPath;
  final String newPath;
  final bool favoriteMigrated;
  final int playlistsMigrated;
  final bool metadataMigrated;
  final bool historyMigrated;

  const LocalMediaRelinkResult({
    required this.oldPath,
    required this.newPath,
    required this.favoriteMigrated,
    required this.playlistsMigrated,
    required this.metadataMigrated,
    required this.historyMigrated,
  });
}

abstract class LocalMediaRelinkService {
  /// Lets the user choose one replacement audio file and relinks the missing
  /// library item. Returns null when the picker is cancelled.
  Future<LocalMediaRelinkResult?> pickReplacementAndRelink(String oldPath);

  /// Relinks directly to [newPath]. Exposed separately so the migration can be
  /// tested without opening a native file picker.
  Future<LocalMediaRelinkResult> relink({
    required String oldPath,
    required String newPath,
  });
}
