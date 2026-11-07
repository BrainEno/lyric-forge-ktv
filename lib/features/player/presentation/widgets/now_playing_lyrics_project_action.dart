import 'package:flutter/material.dart';

import '../../../../core/navigation/routes.dart';
import '../../domain/services/playback_lyrics_availability.dart';
import '../../domain/services/playback_session_service.dart';
import '../playback_screen_dependencies.dart';
import '../screens/immersive_ktv_screen.dart';

class NowPlayingLyricsProjectAction extends StatefulWidget {
  final PlaybackItem item;

  /// Resolves the lyric project behind [item] (and repairs the queue flag).
  final PlaybackLyricsResolver lyricsResolver;

  /// Only used when opening the fullscreen KTV view from this action.
  final ImmersiveKtvDependencies immersiveKtv;

  const NowPlayingLyricsProjectAction({
    super.key,
    required this.item,
    required this.lyricsResolver,
    required this.immersiveKtv,
  });

  @override
  State<NowPlayingLyricsProjectAction> createState() =>
      _NowPlayingLyricsProjectActionState();
}

class _NowPlayingLyricsProjectActionState
    extends State<NowPlayingLyricsProjectAction> {
  late Future<String?> _projectIdFuture;

  @override
  void initState() {
    super.initState();
    _projectIdFuture = _resolve();
  }

  @override
  void didUpdateWidget(covariant NowPlayingLyricsProjectAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItem = oldWidget.item;
    final nextItem = widget.item;
    if (oldItem.id != nextItem.id ||
        oldItem.projectId != nextItem.projectId ||
        oldItem.hasLyrics != nextItem.hasLyrics ||
        oldItem.audioAsset.originalPath != nextItem.audioAsset.originalPath ||
        oldWidget.lyricsResolver != widget.lyricsResolver) {
      _projectIdFuture = _resolve();
    }
  }

  Future<String?> _resolve() async {
    // Resolution also retracts a stale `hasLyrics` flag on the queue item, so
    // opening Now Playing fixes the player bar and quick-play labels too.
    final resolution = await widget.lyricsResolver.resolveAndSync(widget.item);
    return resolution.projectId;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _projectIdFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton.icon(
            onPressed: () => setState(() => _projectIdFuture = _resolve()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('歌词读取失败，重试'),
          );
        }
        final projectId = snapshot.data;
        if (projectId == null || projectId.isEmpty) {
          return const SizedBox.shrink();
        }

        final localLinkedLyrics = widget.item.projectId == null;
        return TextButton.icon(
          onPressed: localLinkedLyrics
              ? () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ImmersiveKtvScreen(
                      initialProjectId: projectId,
                      dependencies: widget.immersiveKtv,
                    ),
                  ),
                )
              : () =>
                    Navigator.pushNamed(context, Routes.playerPath(projectId)),
          icon: Icon(
            localLinkedLyrics ? Icons.fullscreen_rounded : Icons.lyrics_rounded,
          ),
          label: Text(localLinkedLyrics ? '全屏 KTV' : '打开工程播放器'),
        );
      },
    );
  }
}
