import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_lyrics_project_resolver.dart';
import '../../domain/services/playback_session_service.dart';
import '../screens/immersive_ktv_screen.dart';

class NowPlayingLyricsProjectAction extends StatefulWidget {
  final PlaybackItem item;
  final ProjectRepository? projectRepository;
  final LocalMediaMetadataRepository? metadataRepository;

  const NowPlayingLyricsProjectAction({
    super.key,
    required this.item,
    this.projectRepository,
    this.metadataRepository,
  });

  @override
  State<NowPlayingLyricsProjectAction> createState() =>
      _NowPlayingLyricsProjectActionState();
}

class _NowPlayingLyricsProjectActionState
    extends State<NowPlayingLyricsProjectAction> {
  late Future<String?> _projectIdFuture;

  ProjectRepository get _projects =>
      widget.projectRepository ?? ServiceLocatorGlobal.I.projectRepository;

  LocalMediaMetadataRepository get _metadata => widget.metadataRepository ??
      ServiceLocatorGlobal.I.localMediaMetadataRepository;

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
        oldWidget.metadataRepository != widget.metadataRepository) {
      _projectIdFuture = _resolve();
    }
  }

  Future<String?> _resolve() => resolvePlaybackLyricsProjectId(
        item: widget.item,
        projectRepository: _projects,
        metadataRepository: _metadata,
      );

  void _openImmersiveKtv(BuildContext context, String projectId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImmersiveKtvScreen(
          initialProjectId: projectId,
          projectRepository: _projects,
          metadataRepository: _metadata,
        ),
      ),
    );
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
        if (localLinkedLyrics) {
          return TextButton.icon(
            onPressed: () => _openImmersiveKtv(context, projectId),
            icon: const Icon(Icons.fullscreen_rounded),
            label: const Text('全屏 KTV'),
          );
        }

        return TextButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            Routes.playerPath(projectId),
          ),
          icon: const Icon(Icons.lyrics_rounded),
          label: const Text('打开工程播放器'),
        );
      },
    );
  }
}
