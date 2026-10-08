import 'dart:async';

import '../../domain/models/playback_state.dart';
import '../../domain/services/playback_session_service.dart';
import '../../domain/services/remote_playback_item_resolver.dart';

/// Playback-session decorator that refreshes persisted remote queue entries just
/// before they are used. Startup remains offline: automatic refreshing is only
/// enabled after an explicit remote playback action in the current process.
class RemoteRebindingPlaybackSessionService implements PlaybackSessionService {
  final PlaybackSessionService delegate;
  final RemotePlaybackItemResolver resolver;

  late final StreamSubscription<PlaybackSessionState> _subscription;
  bool _remoteRefreshEnabled = false;
  final Set<String> _refreshingIds = <String>{};

  RemoteRebindingPlaybackSessionService({
    required this.delegate,
    required this.resolver,
  }) {
    _subscription = delegate.stateStream.listen(_handleStateChange);
  }

  @override
  Stream<PlaybackSessionState> get stateStream => delegate.stateStream;

  @override
  PlaybackSessionState get currentState => delegate.currentState;

  @override
  PlaybackState get playbackState => delegate.playbackState;

  void _handleStateChange(PlaybackSessionState state) {
    if (!_remoteRefreshEnabled) return;
    final current = state.currentItem;
    if (current == null || !current.isRemoteStream) return;
    unawaited(_refreshItemById(current.id, throwOnFailure: false));
  }

  bool _sameResolvedItem(PlaybackItem a, PlaybackItem b) {
    return a.streamUri == b.streamUri &&
        a.title == b.title &&
        a.artist == b.artist &&
        a.hasLyrics == b.hasLyrics &&
        a.audioAsset.originalPath == b.audioAsset.originalPath &&
        a.audioAsset.format == b.audioAsset.format &&
        a.audioAsset.duration == b.audioAsset.duration &&
        a.audioAsset.metadata['album'] == b.audioAsset.metadata['album'] &&
        a.audioAsset.metadata['remoteArtworkUri'] ==
            b.audioAsset.metadata['remoteArtworkUri'];
  }

  Future<PlaybackItem> _resolve(
    PlaybackItem item, {
    required bool throwOnFailure,
  }) async {
    if (!item.isRemoteStream) return item;
    try {
      return await resolver.resolveForPlayback(item);
    } catch (_) {
      if (throwOnFailure) rethrow;
      return item;
    }
  }

  Future<void> _refreshItemById(
    String id, {
    required bool throwOnFailure,
  }) async {
    if (!_refreshingIds.add(id)) return;
    try {
      final currentQueue = delegate.currentState.queue;
      PlaybackItem? existing;
      for (final item in currentQueue) {
        if (item.id == id) {
          existing = item;
          break;
        }
      }
      if (existing == null || !existing.isRemoteStream) return;
      final resolved = await _resolve(
        existing,
        throwOnFailure: throwOnFailure,
      );
      if (!_sameResolvedItem(existing, resolved)) {
        await delegate.updateItem(resolved);
      }
    } finally {
      _refreshingIds.remove(id);
    }
  }

  Future<PlaybackItem> _resolveForExplicitPlayback(PlaybackItem item) async {
    if (!item.isRemoteStream) return item;
    _remoteRefreshEnabled = true;
    return _resolve(item, throwOnFailure: true);
  }

  @override
  Future<void> playItem(
    PlaybackItem item, {
    Duration? resumeFrom,
  }) async {
    final resolved = await _resolveForExplicitPlayback(item);
    await delegate.playItem(resolved, resumeFrom: resumeFrom);
  }

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    if (!items.any((item) => item.isRemoteStream)) {
      await delegate.setQueue(items, startIndex: startIndex);
      return;
    }

    _remoteRefreshEnabled = true;
    final resolved = <PlaybackItem>[];
    for (final item in items) {
      resolved.add(
        item.isRemoteStream
            ? await _resolve(item, throwOnFailure: true)
            : item,
      );
    }
    await delegate.setQueue(resolved, startIndex: startIndex);
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    final resolved = item.isRemoteStream
        ? await _resolveForExplicitPlayback(item)
        : item;
    await delegate.enqueue(resolved);
  }

  @override
  Future<void> updateItem(PlaybackItem item) => delegate.updateItem(item);

  @override
  Future<void> playAt(int index) async {
    final queue = delegate.currentState.queue;
    if (index >= 0 && index < queue.length && queue[index].isRemoteStream) {
      _remoteRefreshEnabled = true;
      await _refreshItemById(queue[index].id, throwOnFailure: true);
    }
    await delegate.playAt(index);
  }

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
  Future<void> skipPrevious() async {
    final state = delegate.currentState;
    final current = state.currentItem;
    if (current?.isRemoteStream == true) {
      _remoteRefreshEnabled = true;
    }
    if (state.currentIndex > 0) {
      final target = state.queue[state.currentIndex - 1];
      if (target.isRemoteStream) {
        _remoteRefreshEnabled = true;
        await _refreshItemById(target.id, throwOnFailure: true);
      }
    }
    await delegate.skipPrevious();
  }

  @override
  Future<void> skipNext() async {
    final state = delegate.currentState;
    var targetIndex = state.currentIndex + 1;
    if (targetIndex >= state.queue.length &&
        state.repeatMode == PlaybackRepeatMode.all &&
        !state.shuffleEnabled &&
        state.queue.isNotEmpty) {
      targetIndex = 0;
    }
    if (targetIndex >= 0 && targetIndex < state.queue.length) {
      final target = state.queue[targetIndex];
      if (target.isRemoteStream) {
        _remoteRefreshEnabled = true;
        await _refreshItemById(target.id, throwOnFailure: true);
      }
    }
    await delegate.skipNext();
  }

  @override
  Future<void> togglePlayPause() async {
    final current = delegate.currentState.currentItem;
    if (!delegate.playbackState.isPlaying && current?.isRemoteStream == true) {
      _remoteRefreshEnabled = true;
      await _refreshItemById(current!.id, throwOnFailure: true);
    }
    await delegate.togglePlayPause();
  }

  @override
  Future<void> seek(Duration position) => delegate.seek(position);

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await delegate.dispose();
  }
}
