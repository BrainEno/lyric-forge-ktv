import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/services/playback_lyrics_availability.dart';
import '../../domain/services/playback_session_service.dart';

/// App-scoped bridge between the lyrics resolver and the playback queue flag.
///
/// [PlaybackItem.hasLyrics] is a cache that every surface renders
/// synchronously, while the lyric project behind a song can be deleted or
/// created after the song was enqueued. Mounted once around the app shell, this
/// widget re-resolves the current item whenever it changes and pushes the
/// corrected flag through the session, so the player bar, quick play and Now
/// Playing all agree without each surface re-running resolution.
class PlaybackLyricsAvailabilitySync extends StatefulWidget {
  const PlaybackLyricsAvailabilitySync({
    super.key,
    required this.child,
    required this.lyricsResolver,
    required this.playbackSession,
  });

  final Widget child;

  /// Resolves (and repairs) the lyric project behind the current item.
  final PlaybackLyricsResolver lyricsResolver;

  /// Only listened to, so the widget re-resolves when the current item changes.
  final PlaybackSessionService playbackSession;

  @override
  State<PlaybackLyricsAvailabilitySync> createState() =>
      _PlaybackLyricsAvailabilitySyncState();
}

class _PlaybackLyricsAvailabilitySyncState
    extends State<PlaybackLyricsAvailabilitySync> {
  StreamSubscription<PlaybackSessionState>? _subscription;
  String? _syncedKey;

  @override
  void initState() {
    super.initState();
    final session = widget.playbackSession;
    _subscription = session.stateStream.listen(_handleSession);
    _handleSession(session.currentState);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleSession(PlaybackSessionState state) {
    final item = state.currentItem;
    if (item == null || item.isRemoteStream) return;
    final key = _keyFor(item);
    if (key == _syncedKey) return;
    _syncedKey = key;
    unawaited(_sync(item));
  }

  String _keyFor(PlaybackItem item) => [
    item.id,
    item.projectId ?? '',
    item.audioAsset.originalPath,
    item.hasLyrics ? '1' : '0',
  ].join('\u0000');

  Future<void> _sync(PlaybackItem item) async {
    try {
      await widget.lyricsResolver.resolveAndSync(item);
    } catch (_) {
      // A rebuild-path availability refresh is best effort; playback and the
      // already-rendered UI must keep working when storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
