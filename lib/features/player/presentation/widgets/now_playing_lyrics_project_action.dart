import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';

/// Resolves the project that should back the current playback item's lyrics.
///
/// Project queue items already carry [PlaybackItem.projectId]. Local-library
/// items instead keep their lyric relationship in user metadata as
/// `linkedProjectId`, so Now Playing needs to bridge that persisted link before
/// it can enter the existing project/KTV player.
Future<String?> resolvePlaybackLyricsProjectId({
  required PlaybackItem item,
  required ProjectRepository projectRepository,
  required LocalMediaMetadataRepository metadataRepository,
}) async {
  final directProjectId = item.projectId?.trim();
  if (directProjectId != null && directProjectId.isNotEmpty) {
    final project = await projectRepository.getProjectById(directProjectId);
    return project?.id;
  }

  if (item.isRemoteStream || !item.hasLyrics) return null;

  final metadata = await metadataRepository.getForAudio(
    item.audioAsset.originalPath,
  );
  final rawProjectId = metadata?.metadata['linkedProjectId'];
  if (rawProjectId is! String || rawProjectId.trim().isEmpty) return null;

  final project = await projectRepository.getProjectById(rawProjectId.trim());
  if (project == null || !project.hasLyrics) return null;
  return project.id;
}

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
          onPressed: () => Navigator.pushNamed(
            context,
            Routes.playerPath(projectId),
          ),
          icon: const Icon(Icons.lyrics_rounded),
          label: Text(localLinkedLyrics ? '歌词 / KTV' : '打开工程播放器'),
        );
      },
    );
  }
}
