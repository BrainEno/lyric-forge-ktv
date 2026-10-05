import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/services/playback_session_service.dart';

/// Enriches local queue items with cached embedded file tags before delegating
/// to the normal app-scoped playback session. The delegate then applies the
/// user's explicit metadata overrides, preserving this priority:
/// user override > embedded file tag > caller/file-name fallback.
class LibraryMetadataPlaybackSessionService implements PlaybackSessionService {
  final PlaybackSessionService delegate;
  final LocalMediaLibraryRepository libraryRepository;

  const LibraryMetadataPlaybackSessionService({
    required this.delegate,
    required this.libraryRepository,
  });

  @override
  Stream<PlaybackSessionState> get stateStream => delegate.stateStream;

  @override
  PlaybackSessionState get currentState => delegate.currentState;

  @override
  PlaybackState get playbackState => delegate.playbackState;

  Future<PlaybackItem> _enrich(PlaybackItem item) async {
    if (item.projectId != null || item.isRemoteStream) return item;
    LocalMediaLibraryEntry? entry;
    try {
      entry = await libraryRepository.getByPath(item.audioAsset.originalPath);
    } catch (_) {
      return item;
    }
    if (entry == null) return item;

    final title = entry.embeddedTitle?.trim();
    final artist = entry.embeddedArtist?.trim();
    final artwork = entry.embeddedArtworkPath?.trim();
    return item.copyWith(
      title: title == null || title.isEmpty ? item.title : title,
      artist: artist == null || artist.isEmpty ? item.artist : artist,
      artworkPath: artwork == null || artwork.isEmpty ? item.artworkPath : artwork,
    );
  }

  Future<List<PlaybackItem>> _enrichAll(List<PlaybackItem> items) async {
    final result = <PlaybackItem>[];
    for (final item in items) {
      result.add(await _enrich(item));
    }
    return result;
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    await delegate.playItem(await _enrich(item), resumeFrom: resumeFrom);
  }

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    await delegate.setQueue(await _enrichAll(items), startIndex: startIndex);
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    await delegate.enqueue(await _enrich(item));
  }

  @override
  Future<void> updateItem(PlaybackItem item) => delegate.updateItem(item);

  @override
  Future<void> playAt(int index) => delegate.playAt(index);

  @override
  Future<void> removeAt(int index) => delegate.removeAt(index);

  @override
  Future<void> moveItem(int oldIndex, int newIndex) =>
      delegate.moveItem(oldIndex, newIndex);

  @override
  Future<void> clearQueue({bool keepCurrent = true}) =>
      delegate.clearQueue(keepCurrent: keepCurrent);

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      delegate.setShuffleEnabled(enabled);

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) =>
      delegate.setRepeatMode(mode);

  @override
  Future<void> skipPrevious() => delegate.skipPrevious();

  @override
  Future<void> skipNext() => delegate.skipNext();

  @override
  Future<void> togglePlayPause() => delegate.togglePlayPause();

  @override
  Future<void> seek(Duration position) => delegate.seek(position);

  @override
  Future<void> dispose() => delegate.dispose();
}
