import 'package:flutter/material.dart';

import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../../domain/services/playback_lyrics_availability.dart';
import '../../domain/services/playback_session_service.dart';
import '../playback_screen_dependencies.dart';
import '../screens/immersive_ktv_screen.dart';
import 'reference_lyrics_view.dart';

/// The lyric project behind a Now Playing item, and its words when they have
/// no timing (D-054): those are shown as reference text, not as KTV.
class _ResolvedLyrics {
  final String projectId;
  final LyricDocument? reference;

  const _ResolvedLyrics(this.projectId, this.reference);
}

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
  late Future<_ResolvedLyrics?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _resolve();
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
      _lyricsFuture = _resolve();
    }
  }

  Future<_ResolvedLyrics?> _resolve() async {
    // Resolution also retracts a stale `hasLyrics` flag on the queue item, so
    // opening Now Playing fixes the player bar and quick-play labels too.
    final resolution = await widget.lyricsResolver.resolveAndSync(widget.item);
    final projectId = resolution.projectId;
    if (projectId == null || projectId.isEmpty) return null;
    return _ResolvedLyrics(projectId, await _untimedLyrics(projectId));
  }

  /// The project's lyrics when no line is timed; null when they are timed or
  /// cannot be read (the KTV action then behaves as before).
  Future<LyricDocument?> _untimedLyrics(String projectId) async {
    try {
      final project = await widget.lyricsResolver.projectRepository
          .getProjectById(projectId);
      final document = project?.lyricDocument;
      return document != null && document.isUntimed ? document : null;
    } on Object {
      return null;
    }
  }

  Future<void> _showReference(String projectId, LyricDocument document) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      builder: (sheetContext) => SizedBox(
        key: const ValueKey('now-playing-reference-lyrics'),
        height: height,
        child: ReferenceLyricsView(
          lines: document.lines,
          sourceLabel: lyricSourceLabel(document.metadata),
          // A phone has no lyric editor (D-058).
          onOpenEditor: AppCapabilities.lyricWorkbench
              ? () {
                  Navigator.of(sheetContext).pop();
                  Navigator.pushNamed(
                    context,
                    Routes.lyricEditorPath(projectId),
                  );
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedLyrics?>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton.icon(
            onPressed: () => setState(() {
              _lyricsFuture = _resolve();
            }),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('歌词读取失败，重试'),
          );
        }
        final resolved = snapshot.data;
        if (resolved == null) return const SizedBox.shrink();
        final projectId = resolved.projectId;
        final reference = resolved.reference;
        if (reference != null) {
          // Untimed words cannot drive KTV; show them to read along instead.
          return TextButton.icon(
            key: const ValueKey('now-playing-show-reference-lyrics'),
            onPressed: () => _showReference(projectId, reference),
            icon: const Icon(Icons.article_outlined),
            label: const Text('参考歌词'),
          );
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
          label: Text(
            localLinkedLyrics
                ? '全屏 KTV'
                : AppCapabilities.lyricWorkbench
                ? '打开工程播放器'
                : '打开歌词播放器',
          ),
        );
      },
    );
  }
}
