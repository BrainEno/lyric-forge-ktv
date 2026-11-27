import 'dart:io';

import '../../project/domain/models/audio_asset.dart';
import '../domain/models/local_library_browse_item.dart';
import '../domain/models/local_media_library_entry.dart';
import '../domain/models/local_media_metadata.dart';
import '../domain/services/library_lyrics_pairing.dart';
import '../domain/services/media_file_names.dart';
import '../domain/services/playback_session_service.dart';
import 'widgets/library_lyrics_link_text.dart';

class LocalLibraryExplorerSong {
  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? override;
  final DateTime? lastPlayedAt;
  final List<String> playlistNames;

  const LocalLibraryExplorerSong({
    required this.entry,
    required this.override,
    required this.lastPlayedAt,
    required this.playlistNames,
  });

  String get fileName => entry.sourcePath.split(Platform.pathSeparator).last;
  String get fallbackTitle =>
      readableMediaName(
        fileName.replaceAll(
          RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
          '',
        ),
      ) ??
      untitledSongTitle;
  String get title =>
      override?.resolvedTitle(
        entry.embeddedTitle?.trim().isNotEmpty == true
            ? entry.embeddedTitle!
            : fallbackTitle,
      ) ??
      (entry.embeddedTitle?.trim().isNotEmpty == true
          ? entry.embeddedTitle!
          : fallbackTitle);
  String? get artist =>
      override?.resolvedArtist(entry.embeddedArtist) ?? entry.embeddedArtist;
  String? get album =>
      override?.resolvedAlbum(entry.embeddedAlbum) ?? entry.embeddedAlbum;
  String? get artworkPath =>
      override?.resolvedArtwork(entry.embeddedArtworkPath) ??
      entry.embeddedArtworkPath;
  bool get hasLyrics => override?.metadata['linkedProjectId'] is String;

  /// The record of lyrics paired from a file name (D-034), if these are.
  LibraryLyricsPairing? get pairing =>
      hasLyrics ? LibraryLyricsPairing.of(override) : null;
  bool get hasAutoPairedLyrics => pairing != null;
  String get lyricsLabel =>
      hasAutoPairedLyrics ? LibraryLyricsLinkText.autoPairedLabel : '有歌词';
  bool get hasUserOverride => override?.hasOverrides == true;
  bool get playable => !entry.isMissing && File(entry.sourcePath).existsSync();

  LocalLibraryBrowseItem get browseItem => LocalLibraryBrowseItem(
    sourcePath: entry.sourcePath,
    title: title,
    artist: artist,
    album: album,
    genres: entry.embeddedGenres,
    playlistNames: playlistNames,
    addedAt: entry.addedAt,
    lastPlayedAt: lastPlayedAt,
    hasLyrics: hasLyrics,
    hasAutoPairedLyrics: hasAutoPairedLyrics,
    hasUserOverride: hasUserOverride,
    isMissing: entry.isMissing,
  );

  String get secondary => [
    if (artist?.trim().isNotEmpty == true) artist!,
    if (album?.trim().isNotEmpty == true) album!,
    entry.format.toUpperCase(),
    if (hasAutoPairedLyrics) LibraryLyricsLinkText.autoPairedLabel,
  ].join(' · ');

  PlaybackItem get playbackItem => PlaybackItem(
    id: 'local:${entry.sourcePath}',
    title: title,
    artist: artist,
    artworkPath: artworkPath,
    hasLyrics: hasLyrics,
    audioAsset: AudioAsset(
      originalPath: entry.sourcePath,
      format: entry.format,
      thumbnailPath: artworkPath,
    ),
    preferredSource: AudioSourceType.original,
  );
}
