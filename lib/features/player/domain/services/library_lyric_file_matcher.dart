/// A library song that has no lyrics yet, as the matcher sees it.
class LibraryLyricSong {
  const LibraryLyricSong({
    required this.audioPath,
    required this.title,
    this.artist,
  });

  final String audioPath;

  /// The title the library shows: the user's edit, the file's tag, or the
  /// file name.
  final String title;
  final String? artist;
}

/// Why a lyric file was paired with a song, strongest first.
enum LibraryLyricMatchReason {
  /// `夜曲.lrc` next to `夜曲.mp3`.
  besideSong,

  /// `夜曲.lrc` anywhere in the library folder for `夜曲.mp3`.
  sameFileName,

  /// `周杰伦 - 夜曲.lrc` (or `夜曲 - 周杰伦.lrc`) for that artist and title.
  artistAndTitle,

  /// `夜曲.lrc` for a song titled 夜曲: the name an export suggests.
  title,
}

/// One lyric file paired with one song.
class LibraryLyricMatch {
  const LibraryLyricMatch({
    required this.song,
    required this.lyricPath,
    required this.reason,
  });

  final LibraryLyricSong song;
  final String lyricPath;
  final LibraryLyricMatchReason reason;
}

/// Pairs lyric files with library songs by file name (decision D-033).
///
/// The rules are deliberately conservative, because a wrong pairing puts
/// someone else's lyrics on a song:
///
/// * a file is compared on its name without the extension, ignoring case,
///   repeated spaces, the spacing around `-`, and the characters an export
///   replaces with `_` because file systems reject them;
/// * the strongest kind of match wins; when two songs tie at that strength
///   the file is left alone instead of guessing;
/// * a song gets at most one file: the strongest match, then the format
///   listed first in [preferredExtensions], then the path in sort order.
class LibraryLyricFileMatcher {
  const LibraryLyricFileMatcher({
    this.preferredExtensions = const ['lrc', 'ass', 'vtt', 'srt'],
  });

  /// Lyric formats in order of preference when one song has several files.
  final List<String> preferredExtensions;

  List<LibraryLyricMatch> match({
    required List<LibraryLyricSong> songs,
    required Iterable<String> lyricFiles,
  }) {
    final byStemInFolder = <String, List<LibraryLyricSong>>{};
    final byStem = <String, List<LibraryLyricSong>>{};
    final byArtistTitle = <String, List<LibraryLyricSong>>{};
    final byTitle = <String, List<LibraryLyricSong>>{};
    void index(
      Map<String, List<LibraryLyricSong>> map,
      String key,
      LibraryLyricSong song,
    ) {
      if (key.isEmpty) return;
      final list = map.putIfAbsent(key, () => <LibraryLyricSong>[]);
      if (!list.contains(song)) list.add(song);
    }

    for (final song in songs) {
      final stem = nameKey(fileStem(song.audioPath));
      index(byStemInFolder, '${folderKey(song.audioPath)}|$stem', song);
      index(byStem, stem, song);
      final title = nameKey(song.title);
      final artist = nameKey(song.artist ?? '');
      if (artist.isNotEmpty) {
        index(byArtistTitle, '$artist-$title', song);
        index(byArtistTitle, '$title-$artist', song);
      }
      index(byTitle, title, song);
    }

    final best = <LibraryLyricSong, LibraryLyricMatch>{};
    final paths = lyricFiles.toSet().toList()..sort();
    for (final path in paths) {
      final stem = nameKey(fileStem(path));
      if (stem.isEmpty) continue;
      final beside = byStemInFolder['${folderKey(path)}|$stem'];
      final tiers = <(LibraryLyricMatchReason, List<LibraryLyricSong>?)>[
        (LibraryLyricMatchReason.besideSong, beside),
        (LibraryLyricMatchReason.sameFileName, byStem[stem]),
        (LibraryLyricMatchReason.artistAndTitle, byArtistTitle[stem]),
        (LibraryLyricMatchReason.title, byTitle[stem]),
      ];
      for (final (reason, candidates) in tiers) {
        if (candidates == null || candidates.isEmpty) continue;
        // Two songs with equal claim: leave the file for the user.
        if (candidates.length > 1) break;
        final song = candidates.single;
        final match = LibraryLyricMatch(
          song: song,
          lyricPath: path,
          reason: reason,
        );
        final previous = best[song];
        if (previous == null || _isBetter(match, previous)) best[song] = match;
        break;
      }
    }

    // Each file was offered to one song only, so no file is used twice.
    final result = best.values.toList()
      ..sort((a, b) => a.song.audioPath.compareTo(b.song.audioPath));
    return result;
  }

  bool _isBetter(LibraryLyricMatch candidate, LibraryLyricMatch current) {
    if (candidate.reason != current.reason) {
      return candidate.reason.index < current.reason.index;
    }
    final candidateRank = _formatRank(candidate.lyricPath);
    final currentRank = _formatRank(current.lyricPath);
    if (candidateRank != currentRank) return candidateRank < currentRank;
    return candidate.lyricPath.compareTo(current.lyricPath) < 0;
  }

  int _formatRank(String path) {
    final rank = preferredExtensions.indexOf(fileExtension(path));
    return rank < 0 ? preferredExtensions.length : rank;
  }

  /// [text] in the form used for comparison.
  static String nameKey(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\\/:*?"<>|_]+'), ' ')
        .replaceAll(RegExp(r'\s*[-－–—]\s*'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// The file name of [path] without its extension, for `/` or `\` paths.
  static String fileStem(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  /// The lower-case extension of [path], without the dot.
  static String fileExtension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// The folder of [path], compared without case or separator style.
  static String folderKey(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? '' : normalized.substring(0, slash).toLowerCase();
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
