import '../../domain/services/library_lyric_file_matcher.dart';
import '../../domain/services/library_lyrics_auto_linker.dart';
import '../../domain/services/library_lyrics_pairing.dart';

/// Sentences about lyric files paired from the library folder (D-033) and
/// about taking a pairing back (D-034).
abstract final class LibraryLyricsLinkText {
  static const String nothingFound = '没有找到能配对的新歌词文件';

  /// The song card's note for lyrics paired from a file name.
  static const String autoPairedLabel = '自动配对歌词';

  /// The song menu item that takes a pairing back.
  static const String unpairAction = '解除自动配对';

  /// What the dialog promises about the file and later passes.
  static const String unpairPromise = '歌词文件本身不会删除，之后也不会再把它自动配给这首歌。';

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

  /// Why the file was thought to belong to the song, as the dialog says it.
  static String reasonLabel(LibraryLyricMatchReason reason) {
    return switch (reason) {
      LibraryLyricMatchReason.besideSong => '和歌曲在同一个文件夹，文件名相同',
      LibraryLyricMatchReason.sameFileName => '和歌曲的文件名相同',
      LibraryLyricMatchReason.artistAndTitle => '文件名是“歌手 - 歌名”',
      LibraryLyricMatchReason.title => '文件名和歌名相同（没有核对歌手）',
    };
  }

  /// The question before a pairing is taken back.
  static String unpairQuestion(String songTitle, LibraryLyricsPairing pairing) {
    return '「$songTitle」的歌词是按文件名从「${fileName(pairing.lyricPath)}」'
        '自动配上的。解除后这首歌不再显示这份歌词。';
  }

  /// What [LibraryLyricsAutoLinker.unpair] did, for the library's notice.
  static String unpairOutcome(
    String songTitle,
    LibraryLyricsUnpairResult result,
  ) {
    return switch (result.outcome) {
      LibraryLyricsUnpairOutcome.unpaired =>
        '已解除「$songTitle」和「${fileName(result.pairing!.lyricPath)}」的配对',
      LibraryLyricsUnpairOutcome.notAutoPaired => '「$songTitle」的歌词不是自动配对的，没有改动',
      LibraryLyricsUnpairOutcome.editedSincePairing =>
        '「$songTitle」的歌词在配对后改过，为免丢失修改，没有解除',
    };
  }

  /// What undoing an unpairing did.
  static String pairAgainOutcome(
    String songTitle,
    LibraryLyricsLinkResult pass,
  ) {
    if (pass.changedAnything) return '已恢复「$songTitle」的歌词配对';
    if (pass.failed.isNotEmpty) {
      return '没能恢复：歌词文件「${fileName(pass.failed.first)}」读取失败';
    }
    return '没有恢复：「$songTitle」现在已经有歌词了';
  }

  static String unpairFailed(Object error) => '解除配对失败：$error';

  static String _single(LibraryLyricMatch match) {
    final file = fileName(match.lyricPath);
    return '「${match.song.title}」已配上歌词文件「$file」';
  }
}
