import 'dart:io';

import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/services/playback_session_service.dart';

class LocalCollectionSong {
  final String sourcePath;
  final LocalMediaLibraryEntry? entry;
  final LocalMediaMetadata? override;

  const LocalCollectionSong({
    required this.sourcePath,
    required this.entry,
    required this.override,
  });

  String get fileName => sourcePath.split(Platform.pathSeparator).last;

  String get fallbackTitle => fileName.replaceAll(
    RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
    '',
  );

  String get embeddedTitle => entry?.embeddedTitle?.trim().isNotEmpty == true
      ? entry!.embeddedTitle!
      : fallbackTitle;

  String get title => override?.resolvedTitle(embeddedTitle) ?? embeddedTitle;

  String? get artist =>
      override?.resolvedArtist(entry?.embeddedArtist) ?? entry?.embeddedArtist;

  String? get album =>
      override?.resolvedAlbum(entry?.embeddedAlbum) ?? entry?.embeddedAlbum;

  String? get artworkPath =>
      override?.resolvedArtwork(entry?.embeddedArtworkPath) ??
      entry?.embeddedArtworkPath;

  bool get sourceExists => File(sourcePath).existsSync();

  bool get canPlay => entry?.isMissing != true && sourceExists;

  String get format {
    if (entry?.format.trim().isNotEmpty == true) return entry!.format;
    final dot = sourcePath.lastIndexOf('.');
    return dot < 0 ? '' : sourcePath.substring(dot + 1).toLowerCase();
  }

  String get secondary {
    if (!canPlay) return '文件不可用 · 引用仍保留';
    return [
      if (artist?.trim().isNotEmpty == true) artist!,
      if (album?.trim().isNotEmpty == true) album!,
      if (format.isNotEmpty) format.toUpperCase(),
    ].join(' · ');
  }

  PlaybackItem? get playbackItem {
    if (!canPlay) return null;
    return PlaybackItem(
      id: 'local:$sourcePath',
      title: title,
      artist: artist,
      artworkPath: artworkPath,
      hasLyrics: override?.metadata['linkedProjectId'] is String,
      audioAsset: AudioAsset(
        originalPath: sourcePath,
        format: format,
        thumbnailPath: artworkPath,
      ),
      preferredSource: AudioSourceType.original,
    );
  }
}
