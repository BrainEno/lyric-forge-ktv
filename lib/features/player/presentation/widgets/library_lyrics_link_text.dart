import '../../domain/services/library_lyric_file_matcher.dart';
import '../../domain/services/library_lyrics_auto_linker.dart';

/// Sentences about lyric files paired from the library folder (D-033).
abstract final class LibraryLyricsLinkText {
  static const String nothingFound = '没有找到能配对的新歌词文件';

  /// What a pass did, for settings' 立即配对歌词 and the library.
  static String summary(LibraryLyricsLinkResult pass) {
    final linked = pass.linked;
    final failed = pass.failed.length;
    final parts = <String>[
      if (linked.length == 1) _single(linked.single),
      if (linked.length > 1) '已为 ${linked.length} 首歌配上歌词文件',
      if (failed > 0) '$failed 个歌词文件没能读取',
    ];
    return parts.isEmpty ? nothingFound : parts.join('；');
  }

  /// The library's notice after it opens or rescans; null when no song got
  /// lyrics, so opening the library does not repeat old failures.
  static String? libraryNotice(LibraryLyricsLinkResult pass) {
    return pass.changedAnything ? summary(pass) : null;
  }

  static String fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static String _single(LibraryLyricMatch match) {
    final file = fileName(match.lyricPath);
    return '「${match.song.title}」已配上歌词文件「$file」';
  }
}
