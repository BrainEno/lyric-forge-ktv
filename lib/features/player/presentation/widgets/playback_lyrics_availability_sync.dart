import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/audio_path_canonicalizer.dart';
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
    this.projectRepository,
    this.metadataRepository,
    this.playbackSession,
    this.pathCanonicalizer,
  });

  final Widget child;

  /// Optional overrides for tests; production uses the app service locator.
  final ProjectRepository? projectRepository;
  final LocalMediaMetadataRepository? metadataRepository;
  final PlaybackSessionService? playbackSession;
  final AudioPathCanonicalizer? pathCanonicalizer;

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
    try {
      final session =
          widget.playbackSession ??
          ServiceLocatorGlobal.I.playbackSessionService;
      _subscription = session.stateStream.listen(_handleSession);
      _handleSession(session.currentState);
    } catch (_) {
      // The shell is also built in isolation by shell tests, before services
      // exist. Availability sync simply stays idle there.
    }
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
      await resolveAndSyncPlaybackLyrics(
        item: item,
        projectRepository:
            widget.projectRepository ??
            ServiceLocatorGlobal.I.projectRepository,
        metadataRepository:
            widget.metadataRepository ??
            ServiceLocatorGlobal.I.localMediaMetadataRepository,
        playbackSession:
            widget.playbackSession ??
            ServiceLocatorGlobal.I.playbackSessionService,
        pathCanonicalizer:
            widget.pathCanonicalizer ??
            ServiceLocatorGlobal.I.audioPathCanonicalizer,
      );
    } catch (_) {
      // A rebuild-path availability refresh is best effort; playback and the
      // already-rendered UI must keep working when storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
