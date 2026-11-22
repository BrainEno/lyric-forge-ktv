/// The title, artist and length written into an audio file's tags (ID3,
/// Vorbis comments, MP4 atoms).
///
/// Decision D-055: projects are often named after a recording ("新录音 12",
/// "IMG_0034", "2024-05-01 21_30") that no lyric site can find, while the
/// file itself still says what the song is. The tags are a second opinion for
/// the online search, never a replacement for a name the user typed.
class SongTags {
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;

  const SongTags({this.title, this.artist, this.album, this.duration});

  bool get hasTitle => title != null && title!.trim().isNotEmpty;

  bool get isEmpty =>
      !hasTitle &&
      (artist == null || artist!.trim().isEmpty) &&
      (album == null || album!.trim().isEmpty) &&
      duration == null;
}

/// Reads [SongTags] from the audio file at a path; null when the file has
/// none or cannot be read. Implementations must not throw.
typedef SongTagReader = Future<SongTags?> Function(String audioPath);

/// Reads tags for [audioPath] with [reader], giving up after [timeout] and
/// turning every failure into null: the tags only improve a search, so they
/// must never stop one.
Future<SongTags?> readSongTagsSafely(
  SongTagReader? reader,
  String? audioPath, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (reader == null || audioPath == null || audioPath.trim().isEmpty) {
    return null;
  }
  try {
    final tags = await reader(audioPath).timeout(timeout);
    return tags == null || tags.isEmpty ? null : tags;
  } on Object {
    return null;
  }
}
