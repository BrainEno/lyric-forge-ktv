import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../../core/widgets/app_song_row.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

/// The current song and whether it is playing, as a list needs them to mark
/// its playing row (decision D-041).
class NowPlaying {
  const NowPlaying({this.item, this.isPlaying = false});

  /// Nothing loaded.
  static const NowPlaying none = NowPlaying();

  final PlaybackItem? item;
  final bool isPlaying;

  /// The local file of the current song, or null for a stream or nothing.
  String? get localPath {
    final item = this.item;
    if (item == null || item.isRemoteStream) return null;
    return item.audioAsset.originalPath;
  }

  /// How a row for the local file at [sourcePath] should show playback.
  ///
  /// Paths are compared the way the library screens key them: made
  /// absolute, and case folded on Windows only, whose file system ignores
  /// case.
  AppSongRowPlayback playbackForPath(String sourcePath) {
    final current = localPath;
    return AppSongRow.playbackFor(
      isCurrent: current != null && pathKey(current) == pathKey(sourcePath),
      isPlaying: isPlaying,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NowPlaying &&
      other.item?.id == item?.id &&
      other.localPath == localPath &&
      other.isPlaying == isPlaying;

  @override
  int get hashCode => Object.hash(item?.id, localPath, isPlaying);

  /// The comparison key of a local path.
  static String pathKey(String path) {
    final canonical = File(path).absolute.path;
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }
}

/// Rebuilds [builder] whenever the current song or its play/pause state
/// changes, and only then.
///
/// Lists used to read the session once when they loaded, so nothing in them
/// followed the music. This listens to both streams the player bars use —
/// the session for which song, the audio player for playing or paused — and
/// starts from their current values, so the first frame is already right.
///
/// The audio player reports its position several times a second; a list
/// that rebuilt on each report would redo every row for nothing. The
/// listener compares the [NowPlaying] it would build with the last one and
/// rebuilds only when the song or the play/pause state really changed.
class NowPlayingListener extends StatefulWidget {
  const NowPlayingListener({
    super.key,
    required this.playbackSession,
    required this.audioPlayer,
    required this.builder,
  });

  final PlaybackSessionService playbackSession;
  final AudioPlayerService audioPlayer;
  final Widget Function(BuildContext context, NowPlaying nowPlaying) builder;

  @override
  State<NowPlayingListener> createState() => _NowPlayingListenerState();
}

class _NowPlayingListenerState extends State<NowPlayingListener> {
  StreamSubscription<PlaybackSessionState>? _session;
  StreamSubscription<PlaybackState>? _playback;
  PlaybackItem? _item;
  bool _isPlaying = false;
  late NowPlaying _nowPlaying;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant NowPlayingListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playbackSession, widget.playbackSession) ||
        !identical(oldWidget.audioPlayer, widget.audioPlayer)) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    _item = widget.playbackSession.currentState.currentItem;
    _isPlaying = widget.audioPlayer.currentState.isPlaying;
    _nowPlaying = _compose();
    _session = widget.playbackSession.stateStream.listen((state) {
      _item = state.currentItem;
      _update();
    });
    _playback = widget.audioPlayer.stateStream.listen((state) {
      _isPlaying = state.isPlaying;
      _update();
    });
  }

  void _unsubscribe() {
    unawaited(_session?.cancel());
    unawaited(_playback?.cancel());
    _session = null;
    _playback = null;
  }

  NowPlaying _compose() =>
      NowPlaying(item: _item, isPlaying: _item != null && _isPlaying);

  void _update() {
    final next = _compose();
    if (next == _nowPlaying || !mounted) return;
    setState(() => _nowPlaying = next);
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _nowPlaying);
}
