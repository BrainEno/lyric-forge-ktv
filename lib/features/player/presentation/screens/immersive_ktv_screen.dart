import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_chrome_controller.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_lyrics_project_resolver.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/fullscreen_ktv_interaction_surface.dart';

/// Immersive KTV presentation backed by the app-scoped playback session.
///
/// This screen never loads a second player. It observes and controls the shared
/// [PlaybackSessionService], while resolving the lyric project for local-library
/// songs through their persisted `linkedProjectId` relationship.
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

  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  ProjectManifest? _project;
  Object? _loadError;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _projects = widget.projectRepository ??
        ServiceLocatorGlobal.I.projectRepository;
    _metadata = widget.metadataRepository ??
        ServiceLocatorGlobal.I.localMediaMetadataRepository;
    _audio = widget.audioService ?? ServiceLocatorGlobal.I.audioPlayerService;
    _session = widget.playbackSession ??
        ServiceLocatorGlobal.I.playbackSessionService;

    AppChromeController.enterImmersive();
    unawaited(_loadProject(widget.initialProjectId));
    _sessionSubscription = _session.stateStream.listen(_handleSessionChange);
  }

  Future<void> _loadProject(String projectId) async {
    final generation = ++_loadGeneration;
    try {
      final project = await _projects.getProjectById(projectId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _project = project;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _handleSessionChange(PlaybackSessionState state) async {
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
          _loading = false;
          _loadError = null;
        });
        return;
      }
      if (_project?.id == projectId) return;

      final project = await _projects.getProjectById(projectId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _project = project;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _switchSource(AudioSourceType source) async {
    try {
      await _audio.switchSource(source);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法切换到该音源：$error')),
      );
    }
  }

  void _exit() {
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    AppChromeController.exitImmersive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FullscreenKtvInteractionSurface(
      onExit: _exit,
      builder: (context, controlsVisible) {
        return Material(
          color: AppColors.pureBlack,
          child: SafeArea(
            child: StreamBuilder<PlaybackSessionState>(
              stream: _session.stateStream,
              initialData: _session.currentState,
              builder: (context, sessionSnapshot) {
                final session = sessionSnapshot.data ?? _session.currentState;
                return StreamBuilder<PlaybackState>(
                  stream: _audio.stateStream,
                  initialData: _audio.currentState,
                  builder: (context, playbackSnapshot) {
                    final playback =
                        playbackSnapshot.data ?? const PlaybackState.idle();
                    return _ImmersiveKtvBody(
                      project: _project,
                      loading: _loading,
                      loadError: _loadError,
                      session: session,
                      playback: playback,
                      controlsVisible: controlsVisible,
                      onExit: _exit,
                      onSeek: _session.seek,
                      onPlayPause: _session.togglePlayPause,
                      onSkipPrevious: _session.skipPrevious,
                      onSkipNext: _session.skipNext,
                      onSwitchSource: _switchSource,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ImmersiveKtvBody extends StatelessWidget {
  final ProjectManifest? project;
  final bool loading;
  final Object? loadError;
  final PlaybackSessionState session;
  final PlaybackState playback;
  final bool controlsVisible;
  final VoidCallback onExit;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final ValueChanged<AudioSourceType> onSwitchSource;

  const _ImmersiveKtvBody({
    required this.project,
    required this.loading,
    required this.loadError,
    required this.session,
    required this.playback,
    required this.controlsVisible,
    required this.onExit,
    required this.onSeek,
    required this.onPlayPause,
    required this.onSkipPrevious,
    required this.onSkipNext,
    required this.onSwitchSource,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final document = project?.lyricDocument;
    final lyrics = document?.lines ?? const <LyricLine>[];
    final currentIndex = _currentLyricIndex(document, playback.position);
    final availableSources = session.currentItem?.audioAsset.availableSources ??
        const <AudioSourceType>[];

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151515), Color(0xFF050505)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _LyricStage(
              project: project,
              loading: loading,
              loadError: loadError,
              lyrics: lyrics,
              currentIndex: currentIndex,
              spec: spec,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _ControlVisibility(
              visible: controlsVisible,
              child: _TopControls(
                project: project,
                currentItem: session.currentItem,
                availableSources: availableSources,
                currentSource: playback.currentSource,
                onSwitchSource: onSwitchSource,
                onExit: onExit,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ControlVisibility(
              visible: controlsVisible,
              child: _BottomControls(
                playback: playback,
                canSkipPrevious: session.canSkipPrevious,
                canSkipNext: session.canSkipNext,
                onSeek: onSeek,
                onPlayPause: onPlayPause,
                onSkipPrevious: onSkipPrevious,
                onSkipNext: onSkipNext,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlVisibility extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _ControlVisibility({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

class _TopControls extends StatelessWidget {
  final ProjectManifest? project;
  final PlaybackItem? currentItem;
  final List<AudioSourceType> availableSources;
  final AudioSourceType? currentSource;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onExit;

  const _TopControls({
    required this.project,
    required this.currentItem,
    required this.availableSources,
    required this.currentSource,
    required this.onSwitchSource,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(12, 32).toDouble();
    final title = currentItem?.title ?? project?.name ?? 'KTV';
    final itemArtist = currentItem?.artist?.trim();
    final artist = itemArtist?.isNotEmpty == true
        ? itemArtist
        : project?.artist?.trim().isNotEmpty == true
            ? project!.artist
            : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        spec.isShort ? 6 : AppSpacing.md,
        gutter,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (spec.isShort
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.titleLarge)
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (!spec.isShort && artist?.trim().isNotEmpty == true)
                  Text(
                    artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
          if (!spec.isCompact && !spec.isShort)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'ESC / 双击退出 · 移动鼠标显示控制',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          if (availableSources.length > 1)
            PopupMenuButton<AudioSourceType>(
              tooltip: '切换音源',
              icon: const Icon(Icons.tune_rounded),
              onSelected: onSwitchSource,
              itemBuilder: (_) => availableSources
                  .map(
                    (source) => CheckedPopupMenuItem<AudioSourceType>(
                      value: source,
                      checked: source == currentSource,
                      child: Text(_sourceLabel(source)),
                    ),
                  )
                  .toList(growable: false),
            ),
          SizedBox(
            width: spec.minimumInteractiveExtent,
            height: spec.minimumInteractiveExtent,
            child: IconButton.filledTonal(
              tooltip: '退出全屏 KTV',
              onPressed: onExit,
              icon: const Icon(Icons.fullscreen_exit_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricStage extends StatelessWidget {
  final ProjectManifest? project;
  final bool loading;
  final Object? loadError;
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final AppLayoutSpec spec;

  const _LyricStage({
    required this.project,
    required this.loading,
    required this.loadError,
    required this.lyrics,
    required this.currentIndex,
    required this.spec,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter),
          child: Text(
            '歌词工程加载失败：$loadError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }
    if (project == null || lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter),
          child: Text(
            '当前歌曲没有可用歌词',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ),
      );
    }

    final index = (currentIndex ?? 0).clamp(0, lyrics.length - 1).toInt();
    final previous = index > 0 ? lyrics[index - 1] : null;
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;
    final gap = spec.isShort
        ? AppSpacing.sm
        : spec.isCompact
            ? AppSpacing.lg
            : AppSpacing.xxl;
    final maxWidth = spec.isExtraLarge
        ? 1480.0
        : spec.isLarge
            ? 1180.0
            : 900.0;

    final previousStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.headlineSmall)
        ?.copyWith(
      color: AppColors.textTertiary,
      height: 1.35,
      fontWeight: FontWeight.w500,
    );
    final currentStyle = (spec.isShort
            ? Theme.of(context).textTheme.headlineMedium
            : spec.isCompact
                ? Theme.of(context).textTheme.headlineLarge
                : spec.isExtraLarge
                    ? Theme.of(context).textTheme.displayMedium
                    : Theme.of(context).textTheme.displaySmall)
        ?.copyWith(
      color: AppColors.pureWhite,
      fontWeight: FontWeight.w900,
      height: 1.18,
    );
    final nextStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.titleLarge
            : Theme.of(context).textTheme.headlineMedium)
        ?.copyWith(
      color: AppColors.textSecondary,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spec.pageGutter.clamp(16, 48).toDouble(),
            spec.isShort ? 62 : 96,
            spec.pageGutter.clamp(16, 48).toDouble(),
            spec.isShort ? 86 : 138,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AnimatedLyricLine(
                line: previous,
                style: previousStyle,
                maxLines: spec.isShort ? 1 : 2,
              ),
              SizedBox(height: gap),
              _AnimatedLyricLine(
                line: current,
                style: currentStyle,
                maxLines: spec.isShort ? 2 : 3,
              ),
              SizedBox(height: gap),
              _AnimatedLyricLine(
                line: next,
                style: nextStyle,
                maxLines: spec.isShort ? 1 : 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLyricLine extends StatelessWidget {
  final LyricLine? line;
  final TextStyle? style;
  final int maxLines;

  const _AnimatedLyricLine({
    required this.line,
    required this.style,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        line?.text ?? '',
        key: ValueKey<String>(
          '${line?.startTime.inMilliseconds ?? -1}:${line?.text ?? ''}',
        ),
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  final PlaybackState playback;
  final bool canSkipPrevious;
  final bool canSkipNext;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;

  const _BottomControls({
    required this.playback,
    required this.canSkipPrevious,
    required this.canSkipNext,
    required this.onSeek,
    required this.onPlayPause,
    required this.onSkipPrevious,
    required this.onSkipNext,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(12, 32).toDouble();
    final durationMs = playback.duration?.inMilliseconds ?? 0;
    final max = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final value = playback.position.inMilliseconds
        .toDouble()
        .clamp(0.0, max)
        .toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        0,
        gutter,
        spec.isShort ? 6 : AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: max,
              onChanged: durationMs <= 0
                  ? null
                  : (next) => onSeek(
                        Duration(milliseconds: next.round()),
                      ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Text(
                  playback.formattedPosition,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
                const Spacer(),
                Text(
                  playback.formattedDuration,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(height: spec.isShort ? 2 : AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一首',
                onPressed: canSkipPrevious ? onSkipPrevious : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: spec.isShort ? 48 : 58,
                height: spec.isShort ? 48 : 58,
                child: IconButton(
                  tooltip: playback.isPlaying ? '暂停' : '播放',
                  onPressed: playback.isBuffering || playback.isLoading
                      ? null
                      : onPlayPause,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.pureWhite,
                    foregroundColor: AppColors.pureBlack,
                    disabledBackgroundColor: AppColors.textDisabled,
                  ),
                  icon: playback.isBuffering || playback.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pureBlack,
                          ),
                        )
                      : Icon(
                          playback.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 34,
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: '下一首',
                onPressed: canSkipNext ? onSkipNext : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

int? _currentLyricIndex(LyricDocument? document, Duration position) {
  final lines = document?.lines;
  if (lines == null || lines.isEmpty) return null;
  final offset = document?.globalOffset ?? Duration.zero;
  for (var index = lines.length - 1; index >= 0; index--) {
    final shifted = lines[index].startTime + offset;
    final effective = shifted.isNegative ? Duration.zero : shifted;
    if (position >= effective) return index;
  }
  return 0;
}

String _sourceLabel(AudioSourceType source) => switch (source) {
      AudioSourceType.original => '原曲',
      AudioSourceType.instrumental => '伴奏',
      AudioSourceType.vocals => '人声',
    };
