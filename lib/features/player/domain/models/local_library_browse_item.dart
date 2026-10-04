enum LocalLibrarySmartView {
  all,
  recentlyAdded,
  recentlyPlayed,
  withLyrics,
  withoutLyrics,
  editedMetadata,
  missingFiles,
}

enum LocalLibrarySortMode {
  title,
  artist,
  album,
  recentlyAdded,
  recentlyPlayed,
}

class LocalLibraryBrowseItem {
  final String sourcePath;
  final String title;
  final String? artist;
  final String? album;
  final List<String> genres;
  final List<String> playlistNames;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final bool hasLyrics;
  final bool hasUserOverride;
  final bool isMissing;

  const LocalLibraryBrowseItem({
    required this.sourcePath,
    required this.title,
    required this.addedAt,
    this.artist,
    this.album,
    this.genres = const [],
    this.playlistNames = const [],
    this.lastPlayedAt,
    this.hasLyrics = false,
    this.hasUserOverride = false,
    this.isMissing = false,
  });

  String get fileName {
    final normalized = sourcePath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  String get searchText => <String>[
        title,
        artist ?? '',
        album ?? '',
        ...genres,
        ...playlistNames,
        fileName,
        sourcePath,
      ].join('\n').toLowerCase();

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty || searchText.contains(normalized);
  }

  bool matchesSmartView(
    LocalLibrarySmartView view, {
    DateTime? now,
  }) {
    switch (view) {
      case LocalLibrarySmartView.all:
        return true;
      case LocalLibrarySmartView.recentlyAdded:
        final reference = now ?? DateTime.now();
        return !addedAt.isBefore(reference.subtract(const Duration(days: 30)));
      case LocalLibrarySmartView.recentlyPlayed:
        return lastPlayedAt != null;
      case LocalLibrarySmartView.withLyrics:
        return hasLyrics;
      case LocalLibrarySmartView.withoutLyrics:
        return !hasLyrics;
      case LocalLibrarySmartView.editedMetadata:
        return hasUserOverride;
      case LocalLibrarySmartView.missingFiles:
        return isMissing;
    }
  }
}

List<T> queryLocalLibrary<T>({
  required Iterable<T> items,
  required LocalLibraryBrowseItem Function(T item) browseItem,
  String query = '',
  LocalLibrarySmartView smartView = LocalLibrarySmartView.all,
  LocalLibrarySortMode sortMode = LocalLibrarySortMode.title,
  DateTime? now,
}) {
  final result = items.where((item) {
    final value = browseItem(item);
    return value.matchesSmartView(smartView, now: now) &&
        value.matchesQuery(query);
  }).toList(growable: false);

  int compareNullable(String? a, String? b) {
    final left = a?.trim().toLowerCase() ?? '';
    final right = b?.trim().toLowerCase() ?? '';
    if (left.isEmpty && right.isNotEmpty) return 1;
    if (right.isEmpty && left.isNotEmpty) return -1;
    return left.compareTo(right);
  }

  result.sort((leftItem, rightItem) {
    final left = browseItem(leftItem);
    final right = browseItem(rightItem);
    switch (sortMode) {
      case LocalLibrarySortMode.title:
        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
      case LocalLibrarySortMode.artist:
        final artist = compareNullable(left.artist, right.artist);
        return artist != 0
            ? artist
            : left.title.toLowerCase().compareTo(right.title.toLowerCase());
      case LocalLibrarySortMode.album:
        final album = compareNullable(left.album, right.album);
        if (album != 0) return album;
        final artist = compareNullable(left.artist, right.artist);
        return artist != 0
            ? artist
            : left.title.toLowerCase().compareTo(right.title.toLowerCase());
      case LocalLibrarySortMode.recentlyAdded:
        final added = right.addedAt.compareTo(left.addedAt);
        return added != 0
            ? added
            : left.title.toLowerCase().compareTo(right.title.toLowerCase());
      case LocalLibrarySortMode.recentlyPlayed:
        final leftPlayed = left.lastPlayedAt;
        final rightPlayed = right.lastPlayedAt;
        if (leftPlayed == null && rightPlayed != null) return 1;
        if (rightPlayed == null && leftPlayed != null) return -1;
        if (leftPlayed != null && rightPlayed != null) {
          final played = rightPlayed.compareTo(leftPlayed);
          if (played != 0) return played;
        }
        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    }
  });
  return result;
}
