import 'package:flutter/material.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../app/app_services.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/audio_path_canonicalizer.dart';
import '../../domain/services/playback_lyrics_availability.dart';
import '../../domain/services/playback_session_service.dart';
import '../screens/immersive_ktv_screen.dart';

class NowPlayingLyricsProjectAction extends StatefulWidget {
  final PlaybackItem item;
  final ProjectRepository? projectRepository;
  final LocalMediaMetadataRepository? metadataRepository;
  final PlaybackSessionService? playbackSession;
  final AudioPathCanonicalizer? pathCanonicalizer;

  const NowPlayingLyricsProjectAction({
    super.key,
    required this.item,
    this.projectRepository,
    this.metadataRepository,
    this.playbackSession,
    this.pathCanonicalizer,
  });

  @override
  State<NowPlayingLyricsProjectAction> createState() =>
      _NowPlayingLyricsProjectActionState();
}

class _NowPlayingLyricsProjectActionState
    extends State<NowPlayingLyricsProjectAction> {
  late Future<String?> _projectIdFuture;

  ProjectRepository get _projects =>
      widget.projectRepository ?? AppServices.instance.projectRepository;

  LocalMediaMetadataRepository get _metadata =>
      widget.metadataRepository ??
      AppServices.instance.localMediaMetadataRepository;

  PlaybackSessionService get _session =>
      widget.playbackSession ?? AppServices.instance.playbackSessionService;

  AudioPathCanonicalizer get _pathCanonicalizer =>
      widget.pathCanonicalizer ?? AppServices.instance.audioPathCanonicalizer;

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
        oldWidget.projectRepository != widget.projectRepository ||
        oldWidget.metadataRepository != widget.metadataRepository ||
        oldWidget.pathCanonicalizer != widget.pathCanonicalizer) {
      _projectIdFuture = _resolve();
    }
  }

  Future<String?> _resolve() async {
    // Resolution also retracts a stale `hasLyrics` flag on the queue item, so
    // opening Now Playing fixes the player bar and quick-play labels too.
    final resolution = await resolveAndSyncPlaybackLyrics(
      item: widget.item,
      projectRepository: _projects,
      metadataRepository: _metadata,
      playbackSession: _session,
      pathCanonicalizer: _pathCanonicalizer,
    );
    return resolution.projectId;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _projectIdFuture,
      builder: (context, snapshot) {
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
                      projectRepository: _projects,
                      metadataRepository: _metadata,
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
