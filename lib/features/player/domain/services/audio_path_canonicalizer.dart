/// Canonicalizes audio file paths so different spellings of the same file
/// compare equal.
///
/// Playback associates lyric projects with audio by path, but the queue,
/// stored metadata and project manifests can each spell one file's path
/// differently (relative vs absolute, redundant separators, letter case on
/// Windows). Canonicalization needs the platform filesystem, so domain code
/// depends on this contract and the dart:io-backed implementation lives in
/// the data layer.
abstract class AudioPathCanonicalizer {
  /// The canonical comparison form of [path].
  String canonicalize(String path);
}
