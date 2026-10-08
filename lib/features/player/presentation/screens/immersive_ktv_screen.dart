import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_controller.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_lyrics_project_resolver.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/fullscreen_ktv_interaction_surface.dart';
import '../widgets/fullscreen_ktv_lyric_stage.dart';

/// Immersive lyrics view backed by the app-scoped playback session.
class ImmersiveKtvScreen extends StatefulWidget {
  final String initialProjectId;
  final ProjectRepository? projectRepository;
  final LocalMediaMetadataRepository? metadataRepository;
  final AudioPlayerService? audioService;
  final PlaybackSessionService? playbackSession;

  const ImmersiveKtvScreen({
    super.key,
    required this.initialProjectId,
    this.projectRepository,
    this.metadataRepository,
    this.audioService,
    this.playbackSession,
  });

  @override
  State<ImmersiveKtvScreen> createState() => _ImmersiveKtvScreenState();
}

class _ImmersiveKtvScreenState extends State<ImmersiveKtvScreen> {
  late final ProjectRepository _projects;
  late final LocalMediaMetadataRepository _metadata;
  late final AudioPlayerService _audio;
  late final PlaybackSessionService _session;
  StreamSubscription<PlaybackSessionState>? _sessionSub;
  ProjectManifest? _project;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final needsGlobal = widget.projectRepository == null ||
        widget.metadataRepository == null ||
        widget.audioService == null ||
        widget.playbackSession == null;
    final services = needsGlobal ? ServiceLocatorGlobal.I : null;
    _projects = widget.projectRepository ?? services!.projectRepository;
    _metadata =
        widget.metadataRepository ?? services!.localMediaMetadataRepository;
    _audio = widget.audioService ?? services!.audioPlayerService;
    _session = widget.playbackSession ?? services!.playbackSessionService;
    AppChromeController.enterImmersive();
    unawaited(_loadProject(widget.initialProjectId));
    _sessionSub = _session.stateStream.listen(_syncProjectToPlayback);
  }

  Future<void> _loadProject(String projectId) async {
    final generation = ++_loadGeneration;
    try {
      final project = await _projects.getProjectById(projectId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _project = project;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  Future<void> _syncProjectToPlayback(PlaybackSessionState state) async {
    final item = state.currentItem;
    if (item == null) return;
    final generation = ++_loadGeneration;
    try {
      final projectId = await resolvePlaybackLyricsProjectId(
        item: item,
        projectRepository: _projects,
        metadataRepository: _metadata,
      );
      if (!mounted || generation != _loadGeneration) return;
      if (projectId == null) {
        setState(() {
          _project = null;
          _error = null;
        });
        return;
      }
      final project = await _projects.getProjectById(projectId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _project = project;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    AppChromeController.exitImmersive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FullscreenKtvInteractionSurface(
      onExit: () => Navigator.maybePop(context),
      builder: (context, controlsVisible) => Material(
        color: AppColors.pureBlack,
        child: SafeArea(
          child: StreamBuilder<PlaybackSessionState>(
            stream: _session.stateStream,
            initialData: _session.currentState,
            builder: (context, sessionSnapshot) => StreamBuilder<PlaybackState>(
              stream: _audio.stateStream,
              initialData: _audio.currentState,
              builder: (context, playbackSnapshot) {
                final session = sessionSnapshot.data ?? _session.currentState;
                final playback = playbackSnapshot.data ?? _audio.currentState;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _error == null
                          ? FullscreenKtvLyricStage(
                              document: _project?.lyricDocument,
                              position: playback.position,
                            )
                          : Center(
                              child: Text(
                                '歌词加载失败：$_error',
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                    ),
                    _ControlLayer(
                      visible: controlsVisible,
                      title: _project?.name ?? session.currentItem?.title ?? 'KTV',
                      playback: playback,
                      canPrevious: session.canSkipPrevious,
                      canNext: session.canSkipNext,
                      onExit: () => Navigator.maybePop(context),
                      onSeek: _session.seek,
                      onPlayPause: _session.togglePlayPause,
                      onPrevious: _session.skipPrevious,
                      onNext: _session.skipNext,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlLayer extends StatelessWidget {
  final bool visible;
  final String title;
  final PlaybackState playback;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onExit;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _ControlLayer({
    required this.visible,
    required this.title,
    required this.playback,
    required this.canPrevious,
    required this.canNext,
    required this.onExit,
    required this.onSeek,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final durationMs = playback.duration?.inMilliseconds ?? 0;
    final max = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final value = playback.position.inMilliseconds
        .toDouble()
        .clamp(0.0, max)
        .toDouble();
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    tooltip: '退出全屏 KTV',
                    onPressed: onExit,
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  Slider(
                    value: value,
                    min: 0,
                    max: max,
                    onChanged: durationMs <= 0
                        ? null
                        : (next) => onSeek(
                              Duration(milliseconds: next.round()),
                            ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: canPrevious ? onPrevious : null,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      IconButton.filled(
                        onPressed: playback.isLoading || playback.isBuffering
                            ? null
                            : onPlayPause,
                        icon: Icon(
                          playback.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      IconButton(
                        onPressed: canNext ? onNext : null,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
