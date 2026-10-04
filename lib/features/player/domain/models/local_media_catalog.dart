class LocalCatalogTrack {
  final String sourcePath;
  final String format;
  final String title;
  final String? artist;
  final String? album;
  final String? artworkPath;
  final int? trackNumber;
  final int? year;
  final int? durationMs;
  final bool isMissing;
  final bool hasLyrics;

  const LocalCatalogTrack({
    required this.sourcePath,
    required this.format,
    required this.title,
    required this.isMissing,
    this.artist,
    this.album,
    this.artworkPath,
    this.trackNumber,
    this.year,
    this.durationMs,
    this.hasLyrics = false,
  });

  bool get canPlay => !isMissing;
}

class LocalArtistGroup {
  final String name;
  final List<LocalCatalogTrack> tracks;

  const LocalArtistGroup({
    required this.name,
    required this.tracks,
  });

  String? get artworkPath {
    for (final track in tracks) {
      if (track.artworkPath?.trim().isNotEmpty == true) {
        return track.artworkPath;
      }
    }
    return null;
  }

  int get availableTrackCount => tracks.where((track) => track.canPlay).length;

  List<String> get albums {
    final values = <String>{};
    for (final track in tracks) {
      final album = track.album?.trim();
      if (album != null && album.isNotEmpty) values.add(album);
    }
    final result = values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }
}

class LocalAlbumGroup {
  final String title;
  final List<LocalCatalogTrack> tracks;

  const LocalAlbumGroup({
    required this.title,
    required this.tracks,
  });

  String? get artworkPath {
    for (final track in tracks) {
      if (track.artworkPath?.trim().isNotEmpty == true) {
        return track.artworkPath;
      }
    }
    return null;
  }

  int get availableTrackCount => tracks.where((track) => track.canPlay).length;

  List<String> get artists {
    final values = <String>{};
    for (final track in tracks) {
      final artist = track.artist?.trim();
      if (artist != null && artist.isNotEmpty) values.add(artist);
    }
    final result = values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  String get artistLabel {
    final values = artists;
    if (values.isEmpty) return '未知艺人';
    if (values.length == 1) return values.single;
    return '多位艺人';
  }

  int? get year {
    for (final track in tracks) {
      if (track.year != null) return track.year;
    }
    return null;
  }
}

class LocalMediaCatalog {
  final List<LocalCatalogTrack> tracks;
  final List<LocalArtistGroup> artists;
  final List<LocalAlbumGroup> albums;

  const LocalMediaCatalog({
    required this.tracks,
    required this.artists,
    required this.albums,
  });

  static const empty = LocalMediaCatalog(
    tracks: [],
    artists: [],
    albums: [],
  );
}
