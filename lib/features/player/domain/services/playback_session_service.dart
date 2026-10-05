import 'dart:async';

import '../../../project/domain/models/audio_asset.dart';
import '../models/playback_state.dart';

enum PlaybackRepeatMode { off, all, one }

class PlaybackItem {
  final String id;
  final String title;
  final String? artist;
  final String? projectId;
  final String? artworkPath;
  final bool hasLyrics;
  final AudioAsset audioAsset;
  final AudioSourceType preferredSource;

  /// Optional remote URI for streamed playback. Local songs/projects leave this
  /// null and continue to use [audioAsset] file paths.
  final Uri? streamUri;

  const PlaybackItem({
    required this.id,
    required this.title,
    required this.audioAsset,
    this.artist,
    this.projectId,
    this.artworkPath,
    this.hasLyrics = false,
    this.preferredSource = AudioSourceType.original,
    this.streamUri,
  });

  bool get isRemoteStream => streamUri != null;

  PlaybackItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? projectId,
    String? artworkPath,
    bool? hasLyrics,
    AudioAsset? audioAsset,
    AudioSourceType? preferredSource,
    Uri? streamUri,
    bool clearArtist = false,
    bool clearProjectId = false,
    bool clearArtwork = false,
    bool clearStreamUri = false,
  }) {
    return PlaybackItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: clearArtist ? null : artist ?? this.artist,
      projectId: clearProjectId ? null : projectId ?? this.projectId,
      artworkPath: clearArtwork ? null : artworkPath ?? this.artworkPath,
      hasLyrics: hasLyrics ?? this.hasLyrics,
      audioAsset: audioAsset ?? this.audioAsset,
      preferredSource: preferredSource ?? this.preferredSource,
      streamUri: clearStreamUri ? null : streamUri ?? this.streamUri,
    );
  }
}

class PlaybackSessionState {
  final List<PlaybackItem> queue;
  final int currentIndex;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;

  const PlaybackSessionState({
    this.queue = const [],
    this.currentIndex = -1,
    this.shuffleEnabled = false,
    this.repeatMode = PlaybackRepeatMode.off,
  });

  PlaybackItem? get currentItem =>
      currentIndex >= 0 && currentIndex < queue.length
          ? queue[currentIndex]
          : null;

  bool get canSkipPrevious => currentItem != null;
  bool get canSkipNext => currentItem != null &&
      (currentIndex + 1 < queue.length ||
          (repeatMode == PlaybackRepeatMode.all && queue.isNotEmpty));
  int get upcomingCount =>
      currentIndex < 0 ? queue.length : queue.length - currentIndex - 1;

  PlaybackSessionState copyWith({
    List<PlaybackItem>? queue,
    int? currentIndex,
    bool? shuffleEnabled,
    PlaybackRepeatMode? repeatMode,
  }) {
    return PlaybackSessionState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

abstract class PlaybackSessionService {
  Stream<PlaybackSessionState> get stateStream;
  PlaybackSessionState get currentState;
  PlaybackState get playbackState;

  Future<void> playItem(
    PlaybackItem item, {
    Duration? resumeFrom,
  });

  Future<void> setQueue(
    List<PlaybackItem> items, {
    int startIndex = 0,
  });

  Future<void> enqueue(PlaybackItem item);

  /// Replaces the matching queue item without reloading or seeking audio.
  /// Intended for user-edited title/artist/artwork metadata.
  Future<void> updateItem(PlaybackItem item);

  /// Switches playback to an existing item without rebuilding the queue.
  Future<void> playAt(int index);

  /// Removes one queue item. Removing the active item advances to the next
  /// item when possible, otherwise falls back to the previous item.
  Future<void> removeAt(int index);

  /// Moves an item to its final zero-based index while keeping the currently
  /// playing item active even when its position in the queue changes.
  Future<void> moveItem(int oldIndex, int newIndex);

  /// Clears the queue. By default the current item is kept as a one-song queue
  /// so clearing "up next" does not interrupt playback.
  Future<void> clearQueue({bool keepCurrent = true});

  /// Enables/disables shuffle. Enabling keeps the already-played prefix and
  /// current song in place while randomising only upcoming songs. Disabling
  /// restores the queue's pre-shuffle order where those items still exist.
  Future<void> setShuffleEnabled(bool enabled);

  Future<void> setRepeatMode(PlaybackRepeatMode mode);

  Future<void> skipPrevious();
  Future<void> skipNext();
  Future<void> togglePlayPause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}
