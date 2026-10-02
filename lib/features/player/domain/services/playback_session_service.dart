import 'dart:async';

import '../../../project/domain/models/audio_asset.dart';
import '../models/playback_state.dart';

class PlaybackItem {
  final String id;
  final String title;
  final String? artist;
  final String? projectId;
  final String? artworkPath;
  final bool hasLyrics;
  final AudioAsset audioAsset;
  final AudioSourceType preferredSource;

  const PlaybackItem({
    required this.id,
    required this.title,
    required this.audioAsset,
    this.artist,
    this.projectId,
    this.artworkPath,
    this.hasLyrics = false,
    this.preferredSource = AudioSourceType.original,
  });
}

class PlaybackSessionState {
  final List<PlaybackItem> queue;
  final int currentIndex;

  const PlaybackSessionState({
    this.queue = const [],
    this.currentIndex = -1,
  });

  PlaybackItem? get currentItem =>
      currentIndex >= 0 && currentIndex < queue.length
          ? queue[currentIndex]
          : null;

  bool get canSkipPrevious => currentItem != null;
  bool get canSkipNext => currentIndex >= 0 && currentIndex + 1 < queue.length;
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
  Future<void> skipPrevious();
  Future<void> skipNext();
  Future<void> togglePlayPause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}
